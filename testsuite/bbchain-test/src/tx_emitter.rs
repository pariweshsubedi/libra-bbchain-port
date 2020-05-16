// Copyright (c) The Libra Core Contributors
// SPDX-License-Identifier: Apache-2.0

#![forbid(unsafe_code)]

use crate::{instance::Instance,DevProxy};
use cli::{
    commands::{is_address},
};
use config_builder::ValidatorConfig;
use std::{
    slice,
    sync::Arc,
    thread,
    time::{Duration, Instant},
    convert::TryInto,
};

use anyhow::{format_err, Result};
use itertools::zip;
use libra_crypto::{
    ed25519::{Ed25519PrivateKey, Ed25519PublicKey},
    test_utils::KeyPair,
    traits::Uniform,
};
use libra_logger::*;
use libra_types::{
    account_address::AccountAddress,
    account_config::{association_address, lbr_type_tag},
    transaction::{
        authenticator::AuthenticationKey, helpers::create_user_txn, Script, TransactionPayload,
    },
};
use rand::{
    prelude::ThreadRng,
    rngs::{OsRng, StdRng},
    seq::{IteratorRandom, SliceRandom},
    Rng, SeedableRng,
};
use tokio::runtime::{Handle, Runtime};

use futures::{executor::block_on, future::FutureExt};
use libra_json_rpc::JsonRpcAsyncClient;
use libra_types::transaction::{SignedTransaction,parse_as_transaction_argument,TransactionArgument};
use reqwest::{Client, Url};
use std::{
    cmp::{max, min},
    str::FromStr,
    sync::atomic::{AtomicBool, AtomicU64, Ordering},
    fs,
};
use tokio::{task::JoinHandle, time};
use util::retry;

const MAX_TXN_BATCH_SIZE: usize = 100; // Max transactions per account in mempool
const MAX_GAS_AMOUNT: u64 = 1_000_000;
const GAS_UNIT_PRICE: u64 = 0;
const TXN_EXPIRATION_SECONDS: i64 = 50;
const TXN_MAX_WAIT: Duration = Duration::from_secs(TXN_EXPIRATION_SECONDS as u64 + 30);
const LIBRA_PER_NEW_ACCOUNT: u64 = 1_000_000_000;


const NUM_ORG: usize = 1;
const NUM_FACULTIES: usize = 2;
const NUM_COURSES: usize = 1;
const NUM_COURSE_WORKS: usize = 4;
const NUM_OWNERS_PER_COURSE: usize = 3;
const NUM_STUDENTS_PER_COURSE: usize = 1;
const TOTAL_ACCOUNTS: usize = NUM_ORG * NUM_FACULTIES * NUM_COURSES * NUM_COURSE_WORKS;

pub struct TxEmitter {
    accounts: Vec<AccountData>,
    mint_key_pair: KeyPair<Ed25519PrivateKey, Ed25519PublicKey>,
    http_client: Client,
    compiled_scripts: Vec<BBChainScript>,
}

pub struct EmitJob {
    workers: Vec<Worker>,
    stop: Arc<AtomicBool>,
    stats: Arc<TxStats>,
}

#[derive(Default)]
pub struct TxStats {
    pub submitted: AtomicU64,
    pub committed: AtomicU64,
    pub expired: AtomicU64,
}

#[derive(Clone)]
pub struct EmitThreadParams {
    pub wait_millis: u64,
    pub wait_committed: bool,
}

impl Default for EmitThreadParams {
    fn default() -> Self {
        Self {
            wait_millis: 100,
            wait_committed: true,
        }
    }
}

#[derive(Clone)]
pub struct EmitJobRequest {
    pub instances: Vec<Instance>,
    pub accounts_per_client: usize,
    pub workers_per_ac: Option<usize>,
    pub thread_params: EmitThreadParams,
}

impl EmitJobRequest {
    pub fn for_instances(
        instances: Vec<Instance>,
        global_emit_job_request: &Option<EmitJobRequest>,
    ) -> Self {
        match global_emit_job_request {
            Some(global_emit_job_request) => EmitJobRequest {
                instances,
                ..global_emit_job_request.clone()
            },
            None => Self {
                instances,
                accounts_per_client: 15,
                workers_per_ac: None,
                thread_params: EmitThreadParams::default(),
            },
        }
    }
}

impl TxEmitter {
    pub fn new(compiled_scripts: Vec<BBChainScript>) -> Self {
        Self {
            accounts: vec![],
            mint_key_pair: Self::get_mint_key_pair(),
            http_client: Client::new(),
            compiled_scripts: compiled_scripts,
        }
    }

    pub fn get_mint_key_pair() -> KeyPair<Ed25519PrivateKey, Ed25519PublicKey> {
        let seed = "1337133713371337133713371337133713371337133713371337133713371337";
        let seed = hex::decode(seed).expect("Invalid hex in seed.");
        let seed = seed[..32].try_into().expect("Invalid seed");
        let mint_key = ValidatorConfig::new().seed(seed).build_faucet_client();
        KeyPair::from(mint_key)
    }

    pub fn clear(&mut self) {
        self.accounts.clear();
    }

    fn pick_mint_instance<'a, 'b>(&'a self, instances: &'b [Instance]) -> &'b Instance {
        let mut rng = ThreadRng::default();
        instances
            .choose(&mut rng)
            .expect("Instances can not be empty")
    }

    fn pick_mint_client(&self, instances: &[Instance]) -> JsonRpcAsyncClient {
        self.make_client(self.pick_mint_instance(instances))
    }

    pub async fn submit_single_transaction(
        &self,
        instance: &Instance,
        account: &mut AccountData,
    ) -> Result<Instant> {
        let client = self.make_client(instance);
        client
            .submit_transaction(gen_mint_request(account, 10))
            .await?;
        let deadline = Instant::now() + TXN_MAX_WAIT;
        Ok(deadline)
    }

    pub async fn start_job(&mut self, instances: Vec<Instance>) -> Result<EmitJob> {
        // let workers_per_ac = match req.workers_per_ac {
        //     Some(x) => x,
        //     None => {
        //         let target_threads = 300;
        //         // Trying to create somewhere between target_threads/2..target_threads threads
        //         // We want to have equal numbers of threads for each AC, so that they are equally loaded
        //         // Otherwise things like flamegrap/perf going to show different numbers depending on which AC is chosen
        //         // Also limiting number of threads as max 10 per AC for use cases with very small number of nodes or use --peers
        //         min(10, max(1, target_threads / req.instances.len()))
        //     }
        // };
        // let num_clients = req.instances.len() * workers_per_ac;
        // info!(
        //     "Will use {} workers per AC with total {} AC clients",
        //     workers_per_ac, num_clients
        // );
        let accounts_per_client = 10;//TOTAL_ACCOUNTS/instances.len();
        let num_clients = 1;
        let num_accounts = accounts_per_client * num_clients;
        
        println!(
            "Will create {} accounts_per_client with total {} accounts",
            accounts_per_client, num_accounts
        );
        self.mint_accounts(num_accounts, instances.clone()).await?;

        
        let all_accounts = self.accounts.split_off(self.accounts.len() - num_accounts);
        let all_addresses: Vec<_> = all_accounts.iter().map(|d| d.address).collect();
        let all_addresses = Arc::new(all_addresses);
        let stop = Arc::new(AtomicBool::new(false));
        let stats = Arc::new(TxStats::default());
        let tokio_handle = Handle::current();
        let mut all_accounts = all_accounts.into_iter();
        let mut workers = vec![];
        let workers_per_ac = 1;

        println!("All addresses: {:?}", all_addresses);

        
        // for instance in &instances {
        //     println!("Instance loop");
        //     for _ in 0..workers_per_ac {
        //         println!("worker loop");
        //         let client = self.make_client(&instance);
        //         let accounts = (&mut all_accounts).take(accounts_per_client).collect();
        //         let all_addresses = all_addresses.clone();
        //         let stop = stop.clone();
        //         let params = EmitThreadParams::default();
        //         let stats = Arc::clone(&stats);
        //         let compiled_scripts = self.compiled_scripts.clone();
        //         let worker = SubmissionWorker {
        //             accounts,
        //             client,
        //             all_addresses,
        //             stop,
        //             params,
        //             stats,
        //             compiled_scripts
        //         };

        //         println!("worker created");
        //         let join_handle = tokio_handle.spawn(worker.run().boxed());
        //         println!("join handle ran");
        //         workers.push(Worker { join_handle });
        //         println!("pushed worker");
        //     }
        // }
        Ok(EmitJob {
            workers,
            stop,
            stats,
        })
    }

    pub async fn get_bbchain_account(&mut self, instances: Vec<Instance>) -> Result<AccountData>{
        let instance = self.pick_mint_instance(&instances);
        let mut faucet_account = self.load_faucet_account(&instance).await?;

        Ok(faucet_account)
    }

    pub async fn load_faucet_account(&self, instance: &Instance) -> Result<AccountData> {
        let client = self.make_client(instance);
        let address = association_address();
        let sequence_number = query_sequence_numbers(&client, &[address])
            .await
            .map_err(|e| {
                format_err!(
                    "query_sequence_numbers on {:?} for faucet account failed: {}",
                    client,
                    e
                )
            })?[0];
        Ok(AccountData {
            address,
            key_pair: self.mint_key_pair.clone(),
            sequence_number,
        })
    }

    pub async fn mint_accounts(&mut self, num_accounts: usize, instances: Vec<Instance>) -> Result<()> {
        if self.accounts.len() >= num_accounts {
            info!("Not minting accounts");
            return Ok(()); // Early return to skip printing 'Minting ...' logs
        }
        let mut faucet_account = self
            .load_faucet_account(self.pick_mint_instance(&instances))
            .await?;
        let mint_txn = gen_mint_request(
            &mut faucet_account,
            LIBRA_PER_NEW_ACCOUNT * num_accounts as u64,
        );
        execute_and_wait_transactions(
            &mut self.pick_mint_client(&instances),
            &mut faucet_account,
            vec![mint_txn],
        )
        .await?;
        let libra_per_seed =
            (LIBRA_PER_NEW_ACCOUNT * num_accounts as u64) / instances.len() as u64;
        // Create seed accounts with which we can create actual accounts concurrently
        let seed_accounts = create_new_accounts(
            &mut faucet_account,
            instances.len(),
            libra_per_seed,
            100,
            self.pick_mint_client(&instances),
        )
        .await
        .map_err(|e| format_err!("Failed to mint seed_accounts: {}", e))?;
        info!("Completed minting seed accounts");
        // For each seed account, create a thread and transfer libra from that seed account to new accounts
        self.accounts = seed_accounts
            .into_iter()
            .enumerate()
            .map(|(i, mut seed_account)| {
                // Spawn new threads
                let instance = instances[i].clone();
                let num_new_accounts = num_accounts / instances.len();
                let client = self.make_client(&instance);
                thread::spawn(move || {
                    let mut rt = Runtime::new().unwrap();
                    rt.block_on(create_new_accounts(
                        &mut seed_account,
                        num_new_accounts,
                        LIBRA_PER_NEW_ACCOUNT,
                        20,
                        client,
                    ))
                })
            })
            .collect::<Vec<_>>()
            .into_iter()
            .fold(vec![], |mut accumulator, join_handle| {
                // Join threads and accumulate results
                accumulator.extend(
                    join_handle
                        .join()
                        .expect("Failed to join thread")
                        .expect("Failed to mint accounts"),
                );
                accumulator
            });
        info!("Mint is done");
        Ok(())
    }

    pub fn stop_job(&mut self, job: EmitJob) -> TxStats {
        job.stop.store(true, Ordering::Relaxed);
        for worker in job.workers {
            let mut accounts =
                block_on(worker.join_handle).expect("TxEmitter worker thread failed");
            self.accounts.append(&mut accounts);
        }
        #[allow(clippy::match_wild_err_arm)]
        match Arc::try_unwrap(job.stats) {
            Ok(stats) => stats,
            Err(_) => panic!("Failed to unwrap job.stats - worker thread did not exit?"),
        }
    }

    fn make_client(&self, instance: &Instance) -> JsonRpcAsyncClient {
        JsonRpcAsyncClient::new_with_client(
            self.http_client.clone(),
            Url::from_str(format!("http://{}:{}", instance.ip(), instance.ac_port()).as_str())
                .expect("Invalid URL."),
        )
    }

    // pub async fn emit_txn_for(
    //     &mut self,
    //     duration: Duration,
    //     emit_job_request: EmitJobRequest,
    // ) -> Result<TxStats> {
    //     let job = self.start_job(emit_job_request).await?;
    //     tokio::time::delay_for(duration).await;
    //     let stats = self.stop_job(job);
    //     Ok(stats)
    // }

    pub async fn query_sequence_numbers(
        &self,
        instance: &Instance,
        address: &AccountAddress,
    ) -> Result<u64> {
        let client = self.make_client(instance);
        let resp = client
            .get_accounts_state(slice::from_ref(address))
            .await
            .map_err(|e| format_err!("[{:?}] get_accounts_state failed: {:?} ", client, e))?;
        Ok(resp[0]
            .as_ref()
            .ok_or_else(|| format_err!("account does not exist"))?
            .sequence_number)
    }
}

struct Worker {
    join_handle: JoinHandle<Vec<AccountData>>,
}

struct SubmissionWorker {
    accounts: Vec<AccountData>,
    client: JsonRpcAsyncClient,
    all_addresses: Arc<Vec<AccountAddress>>,
    stop: Arc<AtomicBool>,
    params: EmitThreadParams,
    stats: Arc<TxStats>,
    compiled_scripts: Vec<BBChainScript>
}


struct BBChainIssuerEntity{
    account: AccountData,
    sub_issuers: Vec<BBChainIssuerEntity>,
    holders: Vec<AccountData>,
    digests: Vec<Vec<u8>>,
}

struct BBChainHolderEntity{
    account: AccountData,
    issuers: Vec<AccountData>
}

// All initialized organizations
struct BBChainResponse{
    organizations: Vec<BBChainIssuerEntity>
}


// // const NUM_ORG: usize = 1;
// // const NUM_FACULTIES: usize = 2;
// // const NUM_COURSES: usize = 1;
// // const NUM_COURSE_WORKS: usize = 4;
// // const NUM_OWNERS_PER_COURSE: usize = 3;
// // const NUM_STUDENTS_PER_COURSE: usize = 1;
// // const TOTAL_ACCOUNTS: usize = NUM_ORG * NUM_FACULTIES * NUM_COURSES * NUM_COURSE_WORKS;

// // Creates organization structure on chain
// //
// fn init_org(libra_accounts: Vec<AccountData>) -> Result<BBChainResponse>{
//     let organizations = vec![];
//     for org_index in 1..NUM_ORG {
//         //register root issuer
//         let digests = vec![""];

//         for faculty_index in 1..NUM_FACULTIES {
//             //register sub issuer
//             for course_index in 1..NUM_COURSES {
//                 //register sub issuer with NUM_OWNERS_PER_COURSE

//                 for student_index in 1..NUM_STUDENTS_PER_COURSE{
//                     //register student to all issuers
                    
//                     //register student credential

//                 }

//                 // owner signs the credentials


//                 // student claims the credential
//             }
//         }
        
//     }

//     Ok(BBChainResponse{
//         organizations: organizations
//     })
// }



impl SubmissionWorker {
    #[allow(clippy::collapsible_if)]
    async fn run(mut self) -> Vec<AccountData> {

        println!("Worker started");
        let wait = Duration::from_millis(self.params.wait_millis);
        while !self.stop.load(Ordering::Relaxed) {
            println!("Generating requests ....");
            let requests = self.gen_requests();
            println!("Generated requests");
            let num_requests = requests.len();
            for request in requests {
                self.stats.submitted.fetch_add(1, Ordering::Relaxed);
                let wait_util = Instant::now() + wait;
                let resp = self.client.submit_transaction(request).await;
                if let Err(e) = resp {
                    warn!("[{:?}] Failed to submit request: {:?}", self.client, e);
                }
                let now = Instant::now();
                if wait_util > now {
                    time::delay_for(wait_util - now).await;
                }
            }
            if self.params.wait_committed {
                if let Err(uncommitted) =
                    wait_for_accounts_sequence(&self.client, &mut self.accounts).await
                {
                    self.stats
                        .committed
                        .fetch_add((num_requests - uncommitted.len()) as u64, Ordering::Relaxed);
                    self.stats
                        .expired
                        .fetch_add(uncommitted.len() as u64, Ordering::Relaxed);
                    info!(
                        "[{:?}] Transactions were not committed before expiration: {:?}",
                        self.client, uncommitted
                    );
                } else {
                    self.stats
                        .committed
                        .fetch_add(num_requests as u64, Ordering::Relaxed);
                }
            }
        }
        self.accounts
    }

    fn gen_requests(&mut self) -> Vec<SignedTransaction> {
        let mut rng = ThreadRng::default();
        let batch_size = max(MAX_TXN_BATCH_SIZE, self.accounts.len());
        println!("Set batch size");
        let script_compiled_path = self.get_bbchain_compiled_script_path("init_root_issuer", self.compiled_scripts.clone());
        println!("compiled script path : {}", script_compiled_path);
        let accounts = self
            .accounts
            .iter_mut()
            .choose_multiple(&mut rng, batch_size);
        let mut requests = Vec::with_capacity(accounts.len());
        for sender in accounts {
            println!("Starting account call");
            let owner1 = self.all_addresses.choose(&mut rng).expect("all_addresses can't be empty");
            let owner2 = self.all_addresses.choose(&mut rng).expect("all_addresses can't be empty");

            println!("Owners selected");
            
            // let request = gen_transfer_txn_request(sender, receiver, Vec::new(), 1);
            let request = gen_bbchain_txn_request(&*self.compiled_scripts[script_compiled_path].compiled_path, 
                sender, 
                vec![
                    owner1.to_string(),
                    owner2.to_string(),
                    "2".to_string()
                ]
            );

            println!("Request generated");

            requests.push(request);
        }
        requests
    }

    fn get_bbchain_compiled_script_path(&self, script_desc: &str, compiled_scripts: Vec<BBChainScript>) -> usize {
        let mut i:usize = 0;
        for script in compiled_scripts {
            if(&script.desc == script_desc){
                return i;
                // return &*script.compiled_path
            }
            i= i+1;
            // let arguments = vec![];
            // dev.execute_script(&*script.compiled_path, &arguments);
        }
        panic!("BBchain script not found");
    }
}

// create_txn_to_submit
fn gen_bbchain_transaction_to_submit(
    program: TransactionPayload,
    sender_account: &mut AccountData
) -> SignedTransaction {
    let transaction = create_user_txn(
        &sender_account.key_pair,
        program,
        sender_account.address,
        sender_account.sequence_number,
        MAX_GAS_AMOUNT,
        GAS_UNIT_PRICE,
        TXN_EXPIRATION_SECONDS,
    ).expect("Failed to create signed transaction");
    sender_account.sequence_number += 1;
    transaction
}


fn gen_bbchain_txn_request(
    script_compiled_path: &str,
    sender: &mut AccountData,
    args: Vec<String>,
)-> SignedTransaction {
    let script_bytes = fs::read(script_compiled_path).expect("Error reading compiled script");
    let arguments: Vec<_> = args
        .iter()
        .filter_map(|arg| parse_as_transaction_argument_for_client(&*arg).ok())
        .collect();
    
    gen_bbchain_transaction_to_submit(
        TransactionPayload::Script(Script::new(script_bytes, vec![], arguments)),
        sender
    )
    
}

fn parse_as_transaction_argument_for_client(s: &str) -> Result<TransactionArgument> {
    if is_address(s) {
        let account_address = DevProxy::address_from_strings(s)?;
        return Ok(TransactionArgument::Address(account_address));
    }
    parse_as_transaction_argument(s)
}

fn gen_transfer_txn_request(
    sender: &mut AccountData,
    receiver: &AccountAddress,
    receiver_auth_key_prefix: Vec<u8>,
    num_coins: u64,
) -> SignedTransaction {
    gen_submit_transaction_request(
        transaction_builder::encode_transfer_with_metadata_script(
            lbr_type_tag(),
            receiver,
            receiver_auth_key_prefix,
            num_coins,
            vec![],
        ),
        sender,
    )
}

async fn wait_for_accounts_sequence(
    client: &JsonRpcAsyncClient,
    accounts: &mut [AccountData],
) -> Result<(), Vec<(AccountAddress, u64)>> {
    let deadline = Instant::now() + TXN_MAX_WAIT;
    let addresses: Vec<_> = accounts.iter().map(|d| d.address).collect();
    loop {
        match query_sequence_numbers(client, &addresses).await {
            Err(e) => info!(
                "Failed to query ledger info for instance {:?} : {:?}",
                client, e
            ),
            Ok(sequence_numbers) => {
                if is_sequence_equal(accounts, &sequence_numbers) {
                    break;
                }
                let mut uncommitted = vec![];
                if Instant::now() > deadline {
                    for (account, sequence_number) in zip(accounts, &sequence_numbers) {
                        if account.sequence_number != *sequence_number {
                            warn!("Wait deadline exceeded for account {}, expected sequence {}, got from server: {}", account.address, account.sequence_number, sequence_number);
                            uncommitted.push((account.address, *sequence_number));
                            account.sequence_number = *sequence_number;
                        }
                    }
                    return Err(uncommitted);
                }
            }
        }
        time::delay_for(Duration::from_millis(100)).await;
    }
    Ok(())
}

fn is_sequence_equal(accounts: &[AccountData], sequence_numbers: &[u64]) -> bool {
    for (account, sequence_number) in zip(accounts, sequence_numbers) {
        if *sequence_number != account.sequence_number {
            return false;
        }
    }
    true
}

async fn query_sequence_numbers(
    client: &JsonRpcAsyncClient,
    addresses: &[AccountAddress],
) -> Result<Vec<u64>> {
    let mut result = vec![];
    for addresses_batch in addresses.chunks(20) {
        let resp = client
            .get_accounts_state(addresses_batch)
            .await
            .map_err(|e| format_err!("[{:?}] get_accounts_state failed: {:?} ", client, e))?;

        for item in resp.into_iter() {
            result.push(
                item.ok_or_else(|| format_err!("account does not exist"))?
                    .sequence_number,
            );
        }
    }
    Ok(result)
}

fn gen_submit_transaction_request(
    script: Script,
    sender_account: &mut AccountData,
) -> SignedTransaction {
    let transaction = create_user_txn(
        &sender_account.key_pair,
        TransactionPayload::Script(script),
        sender_account.address,
        sender_account.sequence_number,
        MAX_GAS_AMOUNT,
        GAS_UNIT_PRICE,
        TXN_EXPIRATION_SECONDS,
    )
    .expect("Failed to create signed transaction");
    sender_account.sequence_number += 1;
    transaction
}

fn gen_mint_request(faucet_account: &mut AccountData, num_coins: u64) -> SignedTransaction {
    let receiver = faucet_account.address;
    let auth_key_prefix = faucet_account.auth_key_prefix();
    gen_submit_transaction_request(
        transaction_builder::encode_mint_script(
            lbr_type_tag(),
            &receiver,
            auth_key_prefix,
            num_coins,
        ),
        faucet_account,
    )
}

fn gen_random_account(rng: &mut StdRng) -> AccountData {
    let key_pair = KeyPair::generate(rng);
    AccountData {
        address: AccountAddress::from_public_key(&key_pair.public_key),
        key_pair,
        sequence_number: 0,
    }
}

fn gen_random_accounts(num_accounts: usize) -> Vec<AccountData> {
    let seed: [u8; 32] = OsRng.gen();
    let mut rng = StdRng::from_seed(seed);
    (0..num_accounts)
        .map(|_| gen_random_account(&mut rng))
        .collect()
}

fn gen_transfer_txn_requests(
    source_account: &mut AccountData,
    accounts: &[AccountData],
    amount: u64,
) -> Vec<SignedTransaction> {
    accounts
        .iter()
        .map(|account| {
            gen_transfer_txn_request(
                source_account,
                &account.address,
                account.auth_key_prefix(),
                amount,
            )
        })
        .collect()
}

async fn execute_and_wait_transactions(
    client: &mut JsonRpcAsyncClient,
    account: &mut AccountData,
    txn: Vec<SignedTransaction>,
) -> Result<()> {
    debug!(
        "[{:?}] Submitting transactions {} - {} for {}",
        client,
        account.sequence_number - txn.len() as u64,
        account.sequence_number,
        account.address
    );
    for request in txn {
        retry::retry_async(retry::fixed_retry_strategy(5_000, 20), || {
            let request = request.clone();
            let c = client.clone();
            let client_name = format!("{:?}", client);
            Box::pin(async move {
                let txn_str = format!("{}::{}", request.sender(), request.sequence_number());
                debug!("Submitting txn {}", txn_str);
                let resp = c.submit_transaction(request).await;
                debug!("txn {} status: {:?}", txn_str, resp);

                resp.map_err(|e| format_err!("[{}] Failed to submit request: {:?}", client_name, e))
            })
        })
        .await?;
    }
    let r = wait_for_accounts_sequence(client, slice::from_mut(account))
        .await
        .map_err(|_| format_err!("Mint transactions were not committed before expiration"));
    debug!(
        "[{:?}] Account {} is at sequence number {} now",
        client, account.address, account.sequence_number
    );
    r
}

/// Create `num_new_accounts` by transferring libra from `source_account`. Return Vec of created
/// accounts
async fn create_new_accounts(
    source_account: &mut AccountData,
    num_new_accounts: usize,
    libra_per_new_account: u64,
    max_num_accounts_per_batch: u64,
    mut client: JsonRpcAsyncClient,
) -> Result<Vec<AccountData>> {
    let mut i = 0;
    let mut accounts = vec![];
    while i < num_new_accounts {
        let mut batch = gen_random_accounts(min(
            max_num_accounts_per_batch as usize,
            min(MAX_TXN_BATCH_SIZE, num_new_accounts - i),
        ));
        let requests = gen_transfer_txn_requests(source_account, &batch, libra_per_new_account);
        execute_and_wait_transactions(&mut client, source_account, requests).await?;
        i += batch.len();
        accounts.append(&mut batch);
    }
    Ok(accounts)
}

#[derive(Clone)]
pub struct AccountData {
    pub address: AccountAddress,
    pub key_pair: KeyPair<Ed25519PrivateKey, Ed25519PublicKey>,
    pub sequence_number: u64,
}

impl AccountData {
    pub fn auth_key_prefix(&self) -> Vec<u8> {
        AuthenticationKey::ed25519(&self.key_pair.public_key)
            .prefix()
            .to_vec()
    }
}


#[derive(Debug, Clone)]
pub struct BBChainScript{
    pub desc: String,
    pub path: String,
    pub compiled_path: String
}

impl BBChainScript{
    pub fn setCopiledPath(&mut self, path: String){
        self.compiled_path = path;
    }
}
