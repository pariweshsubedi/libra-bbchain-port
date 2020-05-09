use std::{
    env, thread,
    process::{Command, Stdio, Child},
    path::Path,
    time::{Duration},
};
use libra_logger::{info, warn};
use structopt::{clap::ArgGroup, StructOpt};
use libra_temppath::TempPath;

mod client;
mod tx_emitter;
mod instance;
mod dev_proxy;
mod libra_client;

use dev_proxy::{DevProxy};
use tx_emitter::{TxEmitter, AccountData};
use instance::{Instance};
use tokio::{
    runtime::{Builder, Runtime},
    time::{delay_for, delay_until, Instant as TokioInstant},
};


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

    let args = Args::from_args();
    let mut rt = Runtime::new().unwrap();

    //compile modules
    println!("Hello World");
    

    let mut txemitter = TxEmitter::new();
    let instances = setup_instances();
    let mut bbchain_account = rt.block_on(txemitter.get_bbchain_account(instances)).expect("Failed loading bbchain account");
    println!("BBchain address : {}", bbchain_account.address);

    //// rt.block_on(txemitter.open_publishing(setup_instances(), &mut bbchain_account));

    let mut dev = DevProxy::create(bbchain_account).expect("Failed to construct dev proxy.");
    
    println!("Compile World");
    let modules = vec![
        // BBChainModules{
        //     path : "/Users/pariweshsubedi/libra/testsuite/bbchain-test/src/modules/bbchain/Proofs.mvir".to_string(),
        //     deps : vec![
        //         "/Users/pariweshsubedi/libra/language/stdlib".to_string()
        //     ] 
        // },
        BBChainModules{
            path : "/Users/pariweshsubedi/Desktop/UiS/4thsem/project/modules/move/my_module.move".to_string(),
            deps : vec![
                "/Users/pariweshsubedi/libra/language/stdlib/modules".to_string()
            ] 
        },
        BBChainModules{
            path : "/Users/pariweshsubedi/Desktop/UiS/4thsem/project/modules/move/sub_module.move".to_string(),
            deps : vec![
                "/Users/pariweshsubedi/libra/language/stdlib/modules".to_string(),
                "/Users/pariweshsubedi/Desktop/UiS/4thsem/project/modules/move/my_module.move".to_string()
            ] 
        },        
    ];
    for f in &modules {
        println!("Compiling : {}", f.path);
        let compiled_path = dev.compile_modules(f.path.clone(), f.deps.clone()).expect("Failed to compile");
        println!("Publishing Now...");
        dev.publish_module(&compiled_path);
        println!("!! Published !!");
    }
    
    // println!("Hello World");
    // let mut runner = ClusterTestRunner::setup(&args);
    // rt.block_on(runner.start_job());
    
    
    // // start interactive client
    // start_interactive(8080);
}

struct ClusterTestRunner {
    tx_emitter: TxEmitter,
    instances: Vec<Instance>,
    runtime: Runtime,
}

impl ClusterTestRunner {
    /// Discovers cluster, setup log, etc
    pub fn setup(args: &Args) -> Self {
        let tx_emitter = TxEmitter::new();
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

    pub async fn start_job(&self){
        println!("Starting job");
        // self.tx_emitter.start_job(self.instances);
        let time = Duration::from_secs(1);
        let mut emitter = TxEmitter::new();
        let job = emitter
            .start_job(setup_instances())
            .await
            .expect("Failed to start emit job");
        thread::sleep(time);
        // emitter.stop_job(job);
        println!("Completed job");
    }
}

// fn test_cluster(instances: Vec<Instance>){
    
                
// }

fn setup_instances() -> Vec<Instance>{
    let mut instances = Vec::new();
    let instance1 = Instance::new("bbchain1".to_string(), "localhost".to_string(), 8080);
    instances.push(instance1);
    return instances;
}


fn setup_log() {
    if env::var("RUST_LOG").is_err() {
        env::set_var("RUST_LOG", "info");
    }
    ::libra_logger::Logger::new().is_async(true).init();
}

fn start_interactive(port: u16){
    let tmp_mnemonic_file = TempPath::new();
    tmp_mnemonic_file.create_as_file().unwrap();
    let client = client::InteractiveClient::new_with_inherit_io(
        port,
        &tmp_mnemonic_file.path(),
    );
    println!("Loading client...");
    let _output = client.output().expect("Failed to wait on child");
    println!("Exit client.");
}

