module EarmarkedProofs {
    use 0x0000000000000000000000000a550c18::Proofs;
    use 0x0::Transaction;
    use 0x0::Vector;

    struct DigestHolder {
        digests : vector<vector<u8>>,
        holder : address,
        aggregation : vector<u8>
    }

    //--------------------------------
    // Resources
    //--------------------------------

    // A wrapper containing a Libra coin and the address of the recipient the
    // coin is earmarked for.
    resource struct LoggedProofs {
        owners : vector<address>,
        credential_proofs: vector<Proofs::CredentialProof>,
        credentials: vector<Proofs::Credential>
    }

    resource struct DigestHolderProofs {
        digest_holders: vector<DigestHolder>
    }

    resource struct RevocationProofs {
        revoked_digests: vector<vector<u8>>
    }

//     //--------------------------------
//     // Methods
//     //--------------------------------

    public fun is_digest_revoked(digest:  vector<u8>, issuer: address): bool acquires RevocationProofs{
        let requester_revocation_proofs: &RevocationProofs;
        requester_revocation_proofs = borrow_global<RevocationProofs>((issuer));

        // check if the digest is revoked
        Vector::contains< vector<u8>>(&(requester_revocation_proofs).revoked_digests, &digest)
    }

    // Works only if called by issuer
    public fun revoke_digest(digest:  vector<u8>) acquires RevocationProofs{
        let requester_revocation_proofs: &mut RevocationProofs;
        requester_revocation_proofs = borrow_global_mut<RevocationProofs>(Transaction::sender());

        // Transaction::assert that the digest is not already revoked
        Transaction::assert(!Vector::contains< vector<u8>>(&(requester_revocation_proofs).revoked_digests, &digest), 400);
        Vector::push_back< vector<u8>>(
                &mut (requester_revocation_proofs).revoked_digests,
                (digest)
            );   
    }

    public fun getCredentialProofLength(addr: address): u64 acquires LoggedProofs {
        let requester_logged_proofs: &LoggedProofs;
        let len: u64;
        
        requester_logged_proofs = borrow_global<LoggedProofs>((addr));
        len = Vector::length<Proofs::CredentialProof>(&(requester_logged_proofs).credential_proofs);
        len
    }

    public fun getCredentialLength(issuer: address): u64 acquires LoggedProofs {
        let requester_logged_proofs: &LoggedProofs;
        let len: u64;
        
        requester_logged_proofs = borrow_global<LoggedProofs>((issuer));
        len = Vector::length<Proofs::Credential>(&(requester_logged_proofs).credentials);
        len
    }

    public fun hasOwnership(addr: address, issuer: address): bool acquires LoggedProofs {
        let requester_logged_proofs: &LoggedProofs;
        
        requester_logged_proofs = borrow_global<LoggedProofs>((issuer));
        Vector::contains<address>(&(requester_logged_proofs).owners, &addr)
    }

    public fun hasLoggedProofs(addr: address): bool {
        let exists: bool;
        exists = exists<LoggedProofs>((addr));
        exists
    }

    public fun hasRevocationProofs(addr: address): bool {
        let exists: bool;
        exists = exists<RevocationProofs>((addr));
        exists
    }

    public fun createIssuerLoggedProof(_owners: vector<address>){
        move_to_sender<LoggedProofs>(
            LoggedProofs {
                owners: (_owners),
                credential_proofs : Vector::empty<Proofs::CredentialProof>(),
                credentials : Vector::empty<Proofs::Credential>()
            }
        );

        move_to_sender<DigestHolderProofs>(
            DigestHolderProofs {
                digest_holders: Vector::empty<DigestHolder>()
            }
        );

        move_to_sender<RevocationProofs>(
            RevocationProofs {
                revoked_digests: Vector::empty<vector<u8>>()
            }
        );
    }

    // sign credential
    // invoked by : owner
    // TODO:
    // 2 check if quorums on credential has been reached
    // 3  credential to appropriate credential proof
    // 4 compute digest of credential proof based on all included credential
    public fun signCredential(issuer: address, digest: vector<u8>) acquires LoggedProofs{
        let requester_logged_proofs: &mut LoggedProofs;
        let sender_address: address;
        let credential_index:u64;
        let credential_exists:bool;
        let has_consensus: bool;
        
        let owners: &vector<address>;
        let credentials: &mut vector<Proofs::Credential>;
        let credential_proofs: &mut vector<Proofs::CredentialProof>;
        let signed_credential: Proofs::Credential;
        let signed_credential_mut: &mut Proofs::Credential;
        let successfulTransfer: bool;
        
        sender_address = Transaction::sender();

        // 1 sign the credential associated with vector<u8>
        // ownership verification
        requester_logged_proofs = borrow_global_mut<LoggedProofs>((issuer));
        owners = &(requester_logged_proofs).owners;
        credentials = &mut (requester_logged_proofs).credentials;
        credential_proofs = &mut (requester_logged_proofs).credential_proofs;
        Transaction::assert(Vector::contains<address>((owners), &sender_address), 198);

        // Fetch credential
        (credential_index, credential_exists) = Proofs::getCredentialIndexByDigest(freeze((credentials)), &digest);
        Transaction::assert((credential_exists), 199);
        
        signed_credential = Vector::swap_remove<Proofs::Credential>((credentials), (credential_index));
        signed_credential_mut = &mut signed_credential;
        Proofs::signAsOwner((signed_credential_mut));

        // handle signed transactions
        has_consensus = Proofs::hasSignatureConsensus((signed_credential_mut));
        if((has_consensus)){
            // push credential to credential proof
            successfulTransfer = Proofs::insertCredential(
                (credential_proofs), 
                *(signed_credential_mut)
            );
            Transaction::assert((successfulTransfer), 49);
        }else{
            // push credential to logged credentials 
            Vector::push_back<Proofs::Credential>(
                (credentials), 
                *(signed_credential_mut)
            );
        };

        
    }

    // TODO: register credential inserts into earmarked proof credentials vector
    public fun registerCredential(credential: Proofs::Credential) acquires LoggedProofs{
        let requester_logged_proofs: &mut LoggedProofs;

        requester_logged_proofs = borrow_global_mut<LoggedProofs>(Transaction::sender());
         Vector::push_back<Proofs::Credential>(
            &mut (requester_logged_proofs).credentials, 
            (credential)
        );
    }

    // called by issuer when registering CP
    // fails if it is not an issuer running this
    public fun registerCP(cp: Proofs::CredentialProof) acquires LoggedProofs{
        let requester_logged_proofs: &mut LoggedProofs;
        requester_logged_proofs = borrow_global_mut<LoggedProofs>(Transaction::sender());
        Vector::push_back<Proofs::CredentialProof>(
            &mut (requester_logged_proofs).credential_proofs, 
            (cp)
        );
    }

    // called by receipient to claimCP. Can only be claimed if a quorum of owners have signed
    // params : 
    // issuer : address of the issuing course
    public fun claimCP(issuer: address) acquires LoggedProofs, DigestHolderProofs{
        let cp_index: u64;
        let cp_exists: bool;
        let credential_proof: Proofs::CredentialProof;
        let requester_logged_proofs: &mut LoggedProofs;
        let sender_address: address;
        let aggregation: vector<u8>;
        sender_address = Transaction::sender();

        //TODO: validate that issuer knows the sender (in issuerresource.holders)
        requester_logged_proofs = borrow_global_mut<LoggedProofs>((issuer));
        (cp_index, cp_exists) = Proofs::getCredentialProofIndexByHolderAddress(& (requester_logged_proofs).credential_proofs, &sender_address);
        
        // check that a credential proof exists
        Transaction::assert((cp_exists), 42);
        
        // re credential proof from issuer resource
        credential_proof = Vector::swap_remove<Proofs::CredentialProof>(&mut (requester_logged_proofs).credential_proofs, (cp_index));

        // save digest as digest holder proof
        aggregation = createDigestHolderProof(&mut credential_proof, (issuer));

        //  credential proof to holder account
        Proofs::moveCredentialsProofToAccount((credential_proof),(aggregation));
    }

    fun createDigestHolderProof(credential_proof : &mut Proofs::CredentialProof, issuer: address): vector<u8> acquires DigestHolderProofs{
        let digests: vector<vector<u8>>;
        let digest_holder: DigestHolder;
        let requester_dh_proofs: &mut DigestHolderProofs;
        let holder: address;
        let aggregation: vector<u8>;

        requester_dh_proofs = borrow_global_mut<DigestHolderProofs>((issuer));

        holder = Proofs::getCredentialProofHolder(freeze((credential_proof)));
        digests = Proofs::getCredentialProofDigests(freeze((credential_proof)));
        aggregation = Proofs::aggregateDigests(copy digests);
        
        digest_holder = DigestHolder {
            digests : move digests,
            holder : holder,
            aggregation : copy aggregation
        };

        Vector::push_back<DigestHolder>(
            &mut (requester_dh_proofs).digest_holders, 
            (digest_holder)
        );

        aggregation
    }


    public fun aggregateProofs(digests: vector<vector<u8>>): vector<u8>{
        let aggregated_digest: vector<u8>;
        // let aggregated_digest_mut: &mut vector<u8>;
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
    
    //digest - aggregated digest to verify
    public fun verifyCredential(digest: vector<u8>, issuer: address, student: address): bool acquires DigestHolderProofs, RevocationProofs{
        // let local_digest: vector<u8>;
        let requester_dh_proofs: &DigestHolderProofs;
        let len: u64;
        let i: u64;
        let digest_holder_ref: &DigestHolder;

        // check if the digest is revoked
        Transaction::assert(!is_digest_revoked(copy digest, issuer), 400);
        
        // loop through digest holder proof
        // if the digest belongs to student
        i = 0;
        requester_dh_proofs = borrow_global<DigestHolderProofs>((issuer));
        len = Vector::length<DigestHolder>(&(requester_dh_proofs).digest_holders);

        while ((i) < (len)) {
            digest_holder_ref = Vector::borrow<DigestHolder>(&(requester_dh_proofs).digest_holders, (i));
            
            // means that the issuer issued credential proof for the student
            if (student == digest_holder_ref.holder) {
                // check for matching aggregation
                if(copy digest == *&digest_holder_ref.aggregation) return (true)
            };
            i = (i) + 1;
        };        
        false
    }

    public fun generateCredentialAccountDigest(holder:address) acquires DigestHolderProofs{
        let digests: vector<vector<u8>>;
        let aggregated_digest : vector<u8>;
        let requester_dh_proofs: &mut DigestHolderProofs;
        let digest_holder: DigestHolder;
        
        requester_dh_proofs = borrow_global_mut<DigestHolderProofs>(Transaction::sender());
        (digests, aggregated_digest) = Proofs::compileCredentialProof((holder));
        
        digest_holder = DigestHolder {
            digests : move digests,
            holder : holder,
            aggregation : move aggregated_digest
        };

        Vector::push_back<DigestHolder>(
            &mut (requester_dh_proofs).digest_holders, 
            (digest_holder)
        );
        
    }
}