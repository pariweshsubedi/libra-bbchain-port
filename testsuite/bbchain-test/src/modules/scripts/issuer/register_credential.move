use 0x0000000000000000000000000a550c18::Issuer;
fun main(
    student: address,
    digest: vector<u8>
) {
    Issuer::registerCredential(student, digest) ;
}