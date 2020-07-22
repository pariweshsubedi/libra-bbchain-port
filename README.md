
This project is adopted from the libra-1.0.1 (https://github.com/libra/libra) to publish modules and run arbitrary transaction script as the default setting. 
It primarily includes a custom rust package to test custom libra modules developed for document verification in libra blockchain.

# BBchain testsuite 
After [starting a Libra network](https://github.com/pariweshsubedi/libra-kubernetes-document-verification), the `bbchain-test` package present under [testsuite/bbchain-test](https://github.com/pariweshsubedi/libra-bbchain-port/tree/master/testsuite/bbchain-test) can be used to publish modules, scripts and run performance test in your libra network. The bbchain testsuite can be triggered using:

```
cargo run -p bbchain-test
```

This testsuite hosts modules and scripts for credential issuance/verification under the `testsuite/bbchain-test/src/` directory

## Modules for credential issuance/verification
Custom modules created for credential issuance and verification can be found under [testsuite/bbchain-test/src/modules/move](https://github.com/pariweshsubedi/libra-bbchain-port/tree/master/testsuite/bbchain-test/src/modules/move). Here exists three different modules 
- Proofs : This module consists of Libra resources and procedures that helps in credential issuance/verification
- EarmarkedProofs : This module consists of Libra resources and procedures that works as proofs for issuer/owners/holders in the process of credential registration, verification and issuance
- Issuer: This module consists of Libra resources and procedures that allows issuer instantiation with their resources.

## Transaction Scripts for credential issuance/verification
Transaction scripts are included under [testsuite/bbchain-test/src/modules/scripts](https://github.com/pariweshsubedi/libra-bbchain-port/tree/master/testsuite/bbchain-test/src/modules/scripts) and are seperated into directories representing each user group that perform actions through the deployed modules. 

# Running custom libra network with Kubernetes
Please refer to https://github.com/pariweshsubedi/libra-kubernetes-document-verification

# Note for testing other custom modules 
The `bbchain-test` package can be modified to test and publish any custom modules/scripts by defining path to their source and dependencies. 
