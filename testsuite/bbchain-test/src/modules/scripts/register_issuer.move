use 0x0000000000000000000000000a550c18::Issuer;
use 0x0::Vector;
use 0x0::Transaction;
fun main() {
    let exists1: bool;
    let existsLoggedProofs: bool;
    let sender: address;
    let owners: vector<address>;

    // check if issuer resource exists
    exists1 = Issuer::hasIssuerResource({{university}});
    Transaction::assert(exists1 == false, 42);
    
    // define owners
    owners = Vector::empty<address>();
    Vector::push_back<address>(&mut owners, {{mathprofessor}});
    Vector::push_back<address>(&mut owners, {{mathevaluator}});
    
    // register issuer with no parent
    Issuer::registerIssuer(
        owners, // _owners
        0x00, // _parent_issuer
        2, // _quorum
    );
    
    // check if issuer resource exists
    sender = Transaction::sender();
    exists1 = Issuer::hasIssuerResource(copy sender);
    Transaction::assert(exists1, 42);

    // check that issuer has logged proof resource
    existsLoggedProofs = Issuer::hasIssuerResource(copy sender);
    Transaction::assert(existsLoggedProofs, 42);
}