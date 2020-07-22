
This project is adopted from the libra-1.0.1 (https://github.com/libra/libra) to publish modules and run arbitrary transaction script locally as the default setting. 
It primarily includes a custom rust package to test custom libra modules developed for document verification in libra blockchain.

# Testsuite for modules 
After hosting a Libra network, the `bbchain-test` package present under [testsuite/bbchain-test](https://github.com/pariweshsubedi/libra-bbchain-port/tree/master/testsuite/bbchain-test) can be used to publish modules, scripts and run performance test in your libra network. This testsuite hosts modules and scripts for credential issuance/verification under the `modules/` directory

## Modules for credential issuance/verification
Custom modules created for credential issuance and verification can be found under [testsuite/bbchain-test/src/modules/move](https://github.com/pariweshsubedi/libra-bbchain-port/tree/master/testsuite/bbchain-test/src/modules/move). Here exists three different modules 
- Proofs : This module consists of Libra resources and procedures that helps in credential issuance/verification
- EarmarkedProofs : This module consists of Libra resources and procedures that works as proofs for issuer/owners/holders in the process of credential registration, verification and issuance
- Issuer: This module consists of Libra resources and procedures that allows issuer instantiation with their resources.

# Running custom libra network with Kubernetes
Please refer to https://github.com/pariweshsubedi/libra-kubernetes-document-verification

# Note for testing custom modules 
The `bbchain-test` package can be modified with any custom modules by defining ther dependencies and thus can be used to test any other modules too.
