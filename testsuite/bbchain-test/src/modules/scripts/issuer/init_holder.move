use 0x0000000000000000000000000a550c18::Issuer;
use 0x0000000000000000000000000a550c18::Proofs;
use 0x0::Transaction;
fun main(
    issuer: address,
) {
    let exists1: bool;
    // check if issuer resource exists
    exists1 = Proofs::hasCredentialAccount(Transaction::sender());
    Transaction::assert(copy exists1 == false, 42);

    //register to a university
    Issuer::initHolder(issuer);
    
    // check if credential account is created after registration
    exists1 = Proofs::hasCredentialAccount(Transaction::sender());
    Transaction::assert(exists1, 42);
}
// H