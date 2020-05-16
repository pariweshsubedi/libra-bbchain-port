use 0x0000000000000000000000000a550c18::EarmarkedProofs;
use 0x0000000000000000000000000a550c18::Proofs;
use 0x0::Transaction;
fun main(
    course: address,
) {
    EarmarkedProofs::claimCP(copy course);

    // number of earmarked credential proof should decrease to 0
    // it should have been moved to holder's credential account
    Transaction::assert(EarmarkedProofs::getCredentialProofLength(copy course) == 0, 49);

    // student's credential account should now consist of the signed credential proof
    Transaction::assert(Proofs::getCredentialAccountProofLength() == 1, 49);
}