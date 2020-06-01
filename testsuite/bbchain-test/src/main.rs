use std::{
    env, thread,
    time::{Duration, UNIX_EPOCH},
    sync::atomic::Ordering,
};

use structopt::{clap::ArgGroup, StructOpt};
use libra_temppath::TempPath;
use anyhow::{Result};
pub mod client;
pub mod dev_proxy;
pub mod instance;
pub mod libra_client;
pub mod tx_emitter;

use dev_proxy::{DevProxy};
use tx_emitter::{TxEmitter, BBChainScript};
use instance::{Instance};
use tokio::{
    runtime::{Builder, Runtime},
};
use libra_types::{
    waypoint::Waypoint,
};
use chrono::{DateTime, Utc};
use dialoguer::{Confirm};


#[derive(StructOpt, Debug)]
#[structopt(group = ArgGroup::with_name("action"))]
struct Args {
    #[structopt(short = "p", long, default_value = "8080")]
    pub port: u16,
}

struct BBChainModules{
    pub path: String,
    pub deps: Vec<String>,
}

pub fn main() {
    setup_log();
    
    let waypoint = "0:0ace663dbcaa390ee9405559f5e4dbb21f6f34b6bfa609de57518d8088428821";
    let args = Args::from_args();
    let mut rt = Runtime::new().unwrap();

    println!("Hello World");
    
    // Initialize
    let mut txemitter = TxEmitter::new(vec![]);
    let instances = setup_instances();
    let bbchain_account = rt.block_on(txemitter.get_bbchain_account(instances)).expect("Failed loading bbchain account");
    println!("BBchain address : {}", bbchain_account.address);

    let mut dev = DevProxy::create(bbchain_account, waypoint).expect("Failed to construct dev proxy.");

    // Deploy modules - needed the first time after the bbchain libra network is up
    if Confirm::new().with_prompt("\n\nBuild/Deploy modules?").interact().unwrap(){
        build_bbchain_modules(&mut dev);
    } 

    // compile scripts and run test
    if Confirm::new().with_prompt("\n\nCompile scripts and run test transaction ?").interact().unwrap(){
        let compiled_scripts = compile_scripts(&mut dev).expect("failed to compile scripts");

        let runner = ClusterTestRunner::setup(&args,vec![]);
        rt.block_on(runner.start_job(compiled_scripts.clone()));
    } 
    
    // start interactive client
    if Confirm::new().with_prompt("\n\nStart Interactive Client ?").interact().unwrap(){
        start_interactive(8080, waypoint);
    }
}

fn compile_scripts(dev: &mut DevProxy) -> Result<Vec<BBChainScript>> {

    let global_deps = vec![
        "/Users/pariweshsubedi/libra/language/stdlib/modules".to_string(),
        "/Users/pariweshsubedi/libra/testsuite/bbchain-test/src/modules/move/".to_string(),
    ];

    let mut scripts = vec![
        BBChainScript{
            desc: "init_root_issuer".to_string(),
            path: "/Users/pariweshsubedi/libra/testsuite/bbchain-test/src/modules/scripts/issuer/init_root_issuer.move".to_string(),
            compiled_path: "".to_string(),
        },
        BBChainScript{
            desc: "register_sub_issuer".to_string(),
            path: "/Users/pariweshsubedi/libra/testsuite/bbchain-test/src/modules/scripts/issuer/register_sub_issuer.move".to_string(),
            compiled_path: "".to_string(),
        },
        BBChainScript{ // creates credential account for student
            desc: "init_holder".to_string(),
            path: "/Users/pariweshsubedi/libra/testsuite/bbchain-test/src/modules/scripts/issuer/init_holder.move".to_string(),
            compiled_path: "".to_string(),
        },
        BBChainScript{
            desc: "register_holder".to_string(),
            path: "/Users/pariweshsubedi/libra/testsuite/bbchain-test/src/modules/scripts/issuer/register_holder.move".to_string(),
            compiled_path: "".to_string(),
        },
        BBChainScript{
            desc: "register_credential".to_string(),
            path: "/Users/pariweshsubedi/libra/testsuite/bbchain-test/src/modules/scripts/issuer/register_credential.move".to_string(),
            compiled_path: "".to_string(),
        },
        BBChainScript{
            desc: "sign_credential".to_string(),
            path: "/Users/pariweshsubedi/libra/testsuite/bbchain-test/src/modules/scripts/owner/sign_credential.move".to_string(),
            compiled_path: "".to_string(),
        },
        BBChainScript{
            desc: "claim_credential_proof".to_string(),
            path: "/Users/pariweshsubedi/libra/testsuite/bbchain-test/src/modules/scripts/holder/claim_credential_proof.move".to_string(),
            compiled_path: "".to_string(),
        },
        BBChainScript{
            desc: "aggregate_credential_proof".to_string(),
            path: "/Users/pariweshsubedi/libra/testsuite/bbchain-test/src/modules/scripts/issuer/aggregate_credential_proof.move".to_string(),
            compiled_path: "".to_string(),
        },
        BBChainScript{
            desc: "verify_digest".to_string(),
            path: "/Users/pariweshsubedi/libra/testsuite/bbchain-test/src/modules/scripts/verifier/verify_digest.move".to_string(),
            compiled_path: "".to_string(),
        },
    ];

    for script in &mut scripts {
        println!("Compiling : {}", script.path);
        let compiled_path = dev.compile_source(script.path.clone(), global_deps.clone()).expect("Failed to compile");
        script.setCopiledPath(compiled_path);
        println!("compiled path : {}", script.compiled_path);
    };

    Ok(scripts)
}

fn build_bbchain_modules(dev: &mut DevProxy){
    println!("\nBuilding Modules ============================\n");
    let modules = vec![
        BBChainModules{
            path : "/Users/pariweshsubedi/libra/testsuite/bbchain-test/src/modules/move/Proofs.move".to_string(),
            deps : vec![
                "/Users/pariweshsubedi/libra/language/stdlib/modules".to_string()
            ] 
        },
        BBChainModules{
            path : "/Users/pariweshsubedi/libra/testsuite/bbchain-test/src/modules/move/EarmarkedProofs.move".to_string(),
            deps : vec![
                "/Users/pariweshsubedi/libra/language/stdlib/modules".to_string(),
                "/Users/pariweshsubedi/libra/testsuite/bbchain-test/src/modules/move/Proofs.move".to_string()
            ] 
        },
        BBChainModules{
            path : "/Users/pariweshsubedi/libra/testsuite/bbchain-test/src/modules/move/Issuer.move".to_string(),
            deps : vec![
                "/Users/pariweshsubedi/libra/language/stdlib/modules".to_string(),
                "/Users/pariweshsubedi/libra/testsuite/bbchain-test/src/modules/move/Proofs.move".to_string(),
                "/Users/pariweshsubedi/libra/testsuite/bbchain-test/src/modules/move/EarmarkedProofs.move".to_string()
            ]
        },      
    ];

    // deploy modules
    for f in &modules {
        println!("\nCompiling : {}", f.path);
        let compiled_path = dev.compile_source(f.path.clone(), f.deps.clone()).expect("Failed to compile");
        println!("\nPublishing Now...");
        dev.publish_module(&compiled_path).expect("Error publishing module");
        println!("\n!! Published {} !!", f.path);
    }
    println!("\nCompleted Building Modules ============================ \n");
}

struct ClusterTestRunner {
    tx_emitter: TxEmitter,
    instances: Vec<Instance>,
    runtime: Runtime,
}

impl ClusterTestRunner {
    /// Discovers cluster, setup log, etc
    pub fn setup(_args: &Args, compiled_scripts: Vec<BBChainScript>) -> Self {
        let tx_emitter = TxEmitter::new(compiled_scripts);
        let instances = setup_instances();
        let runtime = Builder::new()
            .threaded_scheduler()
            .core_threads(2) //num_cpus::get()
            .thread_name("ct-tokio")
            .enable_all()
            .build()
            .expect("Failed to create tokio runtime");

        ClusterTestRunner{
            tx_emitter: tx_emitter,
            instances: instances,
            runtime: runtime,
        }
    }

    pub async fn start_job(&self, compiled_scripts: Vec<BBChainScript>){
        println!("Starting job");
        // self.tx_emitter.start_job(self.instances);
        let time = Duration::from_secs(5);
        let mut emitter = TxEmitter::new(compiled_scripts);
        let job = emitter
            .start_job(setup_instances())
            .await
            .expect("Failed to start emit job");
        thread::sleep(time);
        let stats = emitter.stop_job(job);

        println!("Submitted : {}", stats.submitted.load(Ordering::Relaxed));
        println!("Committed : {}", stats.committed.load(Ordering::Relaxed));
        println!("Expired : {}", stats.expired.load(Ordering::Relaxed));
        
        // Ok(stats)
        println!("Completed job");
    }
}


fn get_waypoint(client: &mut DevProxy) {
    println!("Retrieving the uptodate ledger info...");
    if let Err(e) = client.test_validator_connection() {
        println!("Failed to get uptodate ledger info connection: {}", e);
        return;
    }

    let latest_epoch_change_li = match client.latest_epoch_change_li() {
        Some(li) => li,
        None => {
            println!("No epoch change LedgerInfo found");
            return;
        }
    };
    let li_time_str = DateTime::<Utc>::from(
        UNIX_EPOCH
            + Duration::from_micros(latest_epoch_change_li.ledger_info().timestamp_usecs()),
    );
    match Waypoint::new_epoch_boundary(latest_epoch_change_li.ledger_info()) {
        Err(e) => println!("Failed to generate a waypoint: {}", e),
        Ok(waypoint) => println!(
            "Waypoint (end of epoch {}, time {}): {}",
            latest_epoch_change_li.ledger_info().epoch(),
            li_time_str,
            waypoint
        ),
    }
}


fn setup_instances() -> Vec<Instance>{
    let mut instances = Vec::new();
    let instance1 = Instance::new("val1".to_string(), "localhost".to_string(), 8080);
    instances.push(instance1);
    
    // let instance2 = Instance::new("val2".to_string(), "localhost".to_string(), 8081);
    // instances.push(instance2);

    // let instance3 = Instance::new("val3".to_string(), "localhost".to_string(), 8082);
    // instances.push(instance3);
    
    return instances;
}

fn setup_log() {
    // if env::var("RUST_LOG").is_err() {
    //     env::set_var("RUST_LOG", "info");
    // }
    env::set_var("RUST_BACKTRACE", "1");
    ::libra_logger::Logger::new().is_async(true).init();
}

fn start_interactive(port: u16, waypointStr: &str){
    let tmp_mnemonic_file = TempPath::new();
    tmp_mnemonic_file.create_as_file().unwrap();
    let client = client::InteractiveClient::new_with_inherit_io(
        port,
        &tmp_mnemonic_file.path(),
        waypointStr
    );
    println!("Loading client...");
    let _output = client.output().expect("Failed to wait on child");
    println!("Exit client.");
}