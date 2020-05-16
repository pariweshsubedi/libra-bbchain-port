use 0x0000000000000000000000000a550c18::Issuer;
use 0x0000000000000000000000000a550c18::EarmarkedProofs;
use 0x0::Vector;
use 0x0::Transaction;
fun main(
    parent_issuer: address,
    owner1: address,
    owner2: address,
    quorum: u64
) {
    let sender: address;
    let owners: vector<address>;

    owners = Vector::empty<address>();
    Vector::push_back<address>(&mut owners, owner1);
    Vector::push_back<address>(&mut owners, owner2);

    sender = Transaction::sender();
    // check that the issuer is not already registered as issuer
    Transaction::assert(Issuer::hasIssuerResource(copy sender) == false, 42);

    // check that issuer has logged proof resource
    Transaction::assert(EarmarkedProofs::hasLoggedProofs(copy sender) == false, 42);
    
    // register issuer(course) with university as parent
    Issuer::registerIssuer(owners, parent_issuer, quorum);
    
    // check if issuer resource in earmarked module was created exists
    Transaction::assert(Issuer::hasIssuerResource(copy sender), 42);
    Transaction::assert(EarmarkedProofs::hasLoggedProofs(copy sender), 42);
    Transaction::assert(EarmarkedProofs::hasRevocationProofs(copy sender), 42);

    // check that the owners are registerd to sign earmarked proofs
    Transaction::assert(Issuer::hasOwnership(owner1, copy sender), 123);
    Transaction::assert(EarmarkedProofs::hasOwnership(owner1, copy sender), 123);
    Transaction::assert(Issuer::hasOwnership(owner2, copy sender), 123);
    Transaction::assert(EarmarkedProofs::hasOwnership(owner2, copy sender), 123);
}

// Course