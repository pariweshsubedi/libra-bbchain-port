use 0x0000000000000000000000000a550c18::Issuer;
fun main(
    student: address
) {
    Issuer::generateCredentialAccountDigest(student);   
}