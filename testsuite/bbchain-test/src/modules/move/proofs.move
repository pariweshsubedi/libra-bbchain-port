module Proofs {
    use 0x0::Transaction;
    use 0x0::Vector;

    struct DummyEvent { 
        b: bool 
    }

    struct Credential{
        digest : vector<u8>,
        holder : address,
        signed : bool,
        revoked : bool,
        time: u64,
        owners_signed : vector<address>,
        owners : vector<address>,
        quorum : u64,
    }

    resource struct CredentialProof{
        quorum: u64,
        holder: address,
        issuer: address,
        owners : vector<address>,
        valid : bool, // signed by quorum of owners
        revoked : bool,
        digest : vector<u8>,
        credentials: vector<Credential>
    }

    resource struct RevocationProof {
        credentialProof: CredentialProof,
        reason: vector<u8>,
        nonce: u64 // counter from issuer
    }

    // stored with holder
    resource struct CredentialAccount{
        issuer : address,
        holder : address,
        credential_proofs : vector<CredentialProof>   
    }

    // // stored with issuer
    resource struct RevocationProofs{
        credential_proofs : vector<RevocationProof>   
    }

    public fun getCredentialAccountProofLength(): u64 acquires CredentialAccount {
        let credential_account_ref: &CredentialAccount;
        let len: u64;
        
        credential_account_ref = borrow_global<CredentialAccount>(Transaction::sender());
        len = Vector::length<CredentialProof>(&credential_account_ref.credential_proofs);
        len
    }

    fun setCredentialProofDigest(credential_proof : &mut CredentialProof, digest: vector<u8>){
        *&mut credential_proof.digest = digest;
    }

    public fun hasCredentialAccount(addr: address): bool {
        exists<CredentialAccount>(addr)
    }

    public fun moveCredentialsProofToAccount(credential_proof: CredentialProof, aggregation: vector<u8>) acquires CredentialAccount{
        let credential_account_ref: &mut CredentialAccount;
        
        // *&mut (credential_proof).digest = h"";
        setCredentialProofDigest(&mut credential_proof, aggregation);

        // TODO : check if credential is valid
        credential_account_ref = borrow_global_mut<CredentialAccount>(Transaction::sender());
        Vector::push_back<CredentialProof>(
            &mut credential_account_ref.credential_proofs, 
            credential_proof
        );
    }

    public fun getCredentialByDigest(credentials: &vector<Credential>, digest: &vector<u8>): (u64 , bool){
        let len: u64;
        let i: u64;
        let credential_ref: &Credential;

        i = 0;
        len = Vector::length<Credential>((credentials));

        while ((i) < (len)) {
            credential_ref = Vector::borrow<Credential>(credentials, i);
            if (*(digest) == *&(credential_ref).digest) return (i, true);
            i = i + 1;
        };

        (0, false)
    }

    public fun getCredentialProofIndexByHolderAddress(credential_proofs: &vector<CredentialProof>,holder :&address): (u64 , bool){
        let len: u64;
        let i: u64;
        let credential_proof_ref: &CredentialProof;

        i = 0;
        len = Vector::length<CredentialProof>((credential_proofs));

        while ((i) < (len)) {
            credential_proof_ref = Vector::borrow<CredentialProof>((credential_proofs), (i));
            
            if (*(holder) == *&(credential_proof_ref).holder) {
                return (i, true)
            };
            i = (i) + 1;
        };

        (0, false)
    }

    public fun getCredentialProofIndexByDigest(credential_proofs: &vector<CredentialProof>, digest: &vector<u8>, check_valid: bool): (u64 , bool) {
        let len: u64;
        let i: u64;
        let credential_proof_ref: &CredentialProof;

        i = 0;
        len = Vector::length<CredentialProof>((credential_proofs));

        while ((i) < (len)) {
            credential_proof_ref = Vector::borrow<CredentialProof>((credential_proofs), (i));
            
            if (*(digest) == *&(credential_proof_ref).digest) {
                if((check_valid)){
                    if(*&(credential_proof_ref).valid){
                        return (i, true)
                    };
                }else{
                    return (i, true)
                };
            };
            i = (i) + 1;
        };

        (0, false)
    }

    public fun getCredentialHolder(_credential: &Credential): address{
        return *&(_credential).holder
    }

    public fun getCredentialProofHolder(_credential_proof: &CredentialProof): address{
        return *&(_credential_proof).holder
    }

    public fun insertCredential(credential_proofs_mut: &mut vector<CredentialProof>, _credential: Credential): bool{
        let len: u64;
        let i: u64;
        let credential_proof_ref: &mut CredentialProof;
        let holder: address;

        holder = getCredentialHolder(& _credential);

        i = 0;
        len = Vector::length<CredentialProof>(freeze((credential_proofs_mut)));
        while (i < len) {
            credential_proof_ref = Vector::borrow_mut<CredentialProof>(credential_proofs_mut, i);
            if (holder == *&(credential_proof_ref).holder) {
                Vector::push_back<Credential>(
                    &mut (credential_proof_ref).credentials, 
                    (_credential)
                );
                return true
            };
            i = (i) + 1;
        };

        false
    }

    public fun getCredentialIndexByDigest(credentials: &vector<Credential>, digest: &vector<u8>): (u64 , bool) {
        let len: u64;
        let i: u64;
        let credential_ref: &Credential;

        i = 0;
        len = Vector::length<Credential>((credentials));

        while ((i) < (len)) {
            credential_ref = Vector::borrow<Credential>((credentials), (i));
            
            if (*(digest) == *&(credential_ref).digest) {
                return (i, true)
            };
            i = (i) + 1;
        };

        (0, false)
    }

    public fun signAsOwner(credential: &mut Credential){
        let sender_address: address;
        let owners: &vector<address>;
        let owners_signed: &mut vector<address>;
        
        sender_address = Transaction::sender();
        owners = &(credential).owners;
        owners_signed = &mut (credential).owners_signed;
        
        Transaction::assert(Vector::contains<address>((owners), &sender_address), 1);
        Transaction::assert(!Vector::contains<address>(freeze((owners_signed)), &sender_address), 1);

        Vector::push_back<address>(
                    (owners_signed), 
                    (sender_address)
                );
    }

    public fun hasSignatureConsensus(credential: &mut Credential): bool{
        let owners_signed_len: u64;
        let owners_signed: &mut vector<address>;
        owners_signed = &mut (credential).owners_signed;
        owners_signed_len = Vector::length<address>(freeze((owners_signed)));
        
        if(owners_signed_len == *&(credential).quorum){
            *&mut (credential).signed = true;
            return (true)
        };
        
        false
    }

    public fun newCredential(holder: address, digest: vector<u8>, _owners: vector<address>, _quorum: u64): Credential{
         Credential{
            digest : (digest),
            holder : (holder),
            signed : false,
            revoked : false,
            time: 1, // replace this with time.now() from newer libra version
            owners_signed : Vector::empty<address>(),
            owners : (_owners),
            quorum: (_quorum)
        }
    }

    public fun newCredentialAccount(_issuer: address, _holder: address){
        move_to_sender<CredentialAccount>(
            CredentialAccount {
                issuer : (_issuer),
                holder : (_holder),
                credential_proofs : Vector::empty<CredentialProof>()
            }
        );
    }

    public fun newCredentialProof(_issuer: address, _holder: address, _quorum: u64, _owners: vector<address>): CredentialProof {
        CredentialProof{
            quorum : (_quorum),
            holder : (_holder),
            issuer : (_issuer),
            owners : (_owners),
            valid : false, 
            revoked : false,
            digest : x"",
            credentials : Vector::empty<Credential>(),
        }     
    }

    public fun getCredentialProofDigests(credential_proof : &CredentialProof): vector<vector<u8>>{
        let digests: vector<vector<u8>>; 
        let len: u64;
        let i: u64;
        let credentials: &vector<Credential>;
        let credential_ref: &Credential;
        let credential_proof_holder : address;

        credential_proof_holder = getCredentialProofHolder((credential_proof));
        credentials = &(credential_proof).credentials;
        digests = Vector::empty<vector<u8>>();

        i = 0;
        len = Vector::length<Credential>((credentials));

        while ((i) < (len)) {
            credential_ref = Vector::borrow<Credential>((credentials), (i));
            Transaction::assert(credential_proof_holder == *&(credential_ref).holder, 890);
            Vector::push_back<vector<u8>>(
                &mut digests, 
                *&(credential_ref).digest
            );
           
            i = (i) + 1;
        };

        digests
    }

    public fun aggregateDigests(digests: vector<vector<u8>>): vector<u8>{
        let aggregated_digest: vector<u8>;
        let digests_mut: &mut vector<vector<u8>>;
        let digest: vector<u8>;
        let len: u64;
        let i: u64;

        aggregated_digest = x"";
        digests_mut = &mut digests;
        i = 0;
        len = Vector::length<vector<u8>>(freeze((digests_mut)));

        loop {
            digest = *Vector::borrow_mut<vector<u8>>((digests_mut), (i));
            Vector::append<u8>(&mut aggregated_digest, (digest));

            i = (i) + 1;
            if ((i) >= (len)) {
                break
            };
        };
        
        aggregated_digest
    }

    // aggregates digests in a credential account
    public fun compileCredentialProof(holder:address): (vector<vector<u8>>,vector<u8>) acquires CredentialAccount{
        let credential_account_ref: &mut CredentialAccount;
        // let digests: vector<vector<u8>>;
        // let aggregated_digest : vector<u8>;
        
        credential_account_ref = borrow_global_mut<CredentialAccount>((holder));
        Transaction::assert(*&(credential_account_ref).issuer == Transaction::sender(), 90);
        
        aggregateCredentialProofs(&(credential_account_ref).credential_proofs)
        // *&mut (credential_account_ref).digest = (aggregated_digest);
    }

    // aggregate credential proof digests
    public fun aggregateCredentialProofs(credential_proofs: &vector<CredentialProof>): (vector<vector<u8>> , vector<u8>){
        let digests: vector<vector<u8>>;
        let credential_proof_ref: &CredentialProof;
        let len: u64;
        let i: u64;
        let digests_copy: vector<vector<u8>>;
        
        i = 0;
        len = Vector::length<CredentialProof>((credential_proofs));
        digests = Vector::empty<vector<u8>>();
        digests_copy = Vector::empty<vector<u8>>();

        while ((i) < (len)) {
            credential_proof_ref = Vector::borrow<CredentialProof>((credential_proofs), (i));
            
            Vector::push_back<vector<u8>>(
                &mut digests, 
                *&(credential_proof_ref).digest
            );

            Vector::push_back<vector<u8>>(
                &mut digests_copy, 
                *&(credential_proof_ref).digest
            );
            
            i = (i) + 1;
        };
        
        (digests_copy, aggregateDigests(digests))
    }

}