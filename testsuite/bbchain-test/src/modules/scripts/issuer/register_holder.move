use 0x0000000000000000000000000a550c18::Issuer;
use 0x0000000000000000000000000a550c18::EarmarkedProofs;
use 0x0::Transaction;
fun main(
    holder: address,
) {
    // register student to course
    Issuer::registerHolder(holder);

    // check if a credential proof is registered in earmarked proof
    Transaction::assert(EarmarkedProofs::getCredentialProofLength(Transaction::sender()) == 1, 49);
}

// Course