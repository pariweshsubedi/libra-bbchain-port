use 0x0000000000000000000000000a550c18::Issuer;

fun main(
    digest: vector<u8>,
    issuer: address,
    holder: address
) {
    Issuer::verifyCredential(digest, issuer, holder); 
}
