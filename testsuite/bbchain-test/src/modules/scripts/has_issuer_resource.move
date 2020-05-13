use 0x0000000000000000000000000a550c18::Issuer;
use 0x0::Transaction;
fun main() {
    let exists1: bool;
    // check if issuer resource exists
    exists1 = Issuer::hasIssuerResource(Transaction::sender());
    Transaction::assert(exists1 == false, 42);
}