use 0x0000000000000000000000000a550c18::Issuer;
use 0x0::Vector;
use 0x0::Transaction;
fun main(    
    owner1: address,
    owner2: address,
    quorum: u64
) {
    let exists1: bool;
    let existsLoggedProofs: bool;
    let sender: address;
    let owners: vector<address>;

    sender = Transaction::sender();

    // check if issuer resource exists
    exists1 = Issuer::hasIssuerResource(copy sender);
    Transaction::assert(exists1 == false, 42);
    
    // define owners
    owners = Vector::empty<address>();
    Vector::push_back<address>(&mut owners, owner1);
    Vector::push_back<address>(&mut owners, owner2);
    
    // register issuer with no parent
    Issuer::registerIssuer(
        owners, // _owners
        0x00, // _parent_issuer
        quorum, // _quorum
    );
    
    // check if issuer resource exists
    exists1 = Issuer::hasIssuerResource(copy sender);
    Transaction::assert(exists1, 42);

    // check that issuer has logged proof resource
    existsLoggedProofs = Issuer::hasIssuerResource(copy sender);
    Transaction::assert(existsLoggedProofs, 42);
}
// I