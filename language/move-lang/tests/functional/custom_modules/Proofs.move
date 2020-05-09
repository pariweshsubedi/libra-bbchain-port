//! account: bbchain, 1000000000
//! account: university, 1000000000
//! account: mathcourse, 1000000000
//! account: anothercourse, 1000000000
//! account: mathprofessor, 1000000000
//! account: mathevaluator, 1000000000
//! account: student1, 1000000000
//! account: student2, 1000000000
//! account: verifier, 1000000000

//! new-transaction
//! sender: bbchain
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

//! new-transaction
//! sender: bbchain
// module that allows issuer to mark a credential resource for recepients
module EarmarkedProofs {
    use {{bbchain}}::Proofs;
    use 0x0::Transaction;
    use 0x0::Vector;
    // import 0x0.Hash;

//     struct MyEvent { 
//         b: bool 
//     }

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


//     // Events
//     public fun emit_event(val: bool) {
//         let handle: LibraAccount.EventHandle<MyEvent>;
//         handle = LibraAccount.new_event_handle<MyEvent>();
//         LibraAccount.emit_event<MyEvent>(&mut handle, MyEvent{ b: (val) });
//         LibraAccount.destroy_handle<MyEvent>((handle));
//         
//     }

//     // TODO: Aggregate credential proof as a root issuer
//     public fun aggregateCredentialProofs(holder:address){
//         
//     }
}

//! new-transaction
//! sender: bbchain
module Issuer {
    use {{bbchain}}::Proofs;
    use {{bbchain}}::EarmarkedProofs;
    use 0x0::Transaction;
    use 0x0::Vector;

    // --------------------------------
    // Resources
    // --------------------------------
    resource struct IssuerResource{
        owners : vector<address>,
        sub_issuers : vector<address>,
        parent_issuer : address,
        holders : vector<address>,
        digests : vector<vector<u8>>,
        revoked_digests : vector<vector<u8>>,
        nonce: u64, // counter for each issue/revoke operation because it modifies ledger state
        quorum : u64
    }

    //--------------------------------
    // Methods
    //--------------------------------

    // Can only be invoked by credential account issuer. Ex: uni
    public fun generateCredentialAccountDigest(holder:address){
        EarmarkedProofs::generateCredentialAccountDigest((holder));
    }

    public fun signCredential(issuer: address, digest: vector<u8>){
        EarmarkedProofs::signCredential((issuer), (digest));
    }

    public fun verifyCredential(digest: vector<u8>, issuer: address, holder: address): bool acquires IssuerResource{
        let requester_account_ref: &IssuerResource;
        requester_account_ref = borrow_global<IssuerResource>((issuer));

        // assert that the digest hasnt been revoked
        Transaction::assert(!Vector::contains<vector<u8>>(&(requester_account_ref).revoked_digests, &digest), 10);

        // loop through digest issuer proof and verify that the digest belongs to the student
        EarmarkedProofs::verifyCredential(digest, issuer, holder)
    }

    public fun hasOwnership(addr: address, issuer: address): bool acquires IssuerResource{
        let requester_account_ref: &IssuerResource;
        requester_account_ref = borrow_global<IssuerResource>(issuer);

        Vector::contains<address>(&(requester_account_ref).owners, &addr)
    }

    public fun hasEnrollment(holder: address, issuer: address): bool acquires IssuerResource{
        let requester_account_ref: &IssuerResource;
        requester_account_ref = borrow_global<IssuerResource>((issuer));

        Vector::contains<address>(&(requester_account_ref).holders, &holder)
    }


    public fun registerIssuer(_owners: vector<address>, _parent_issuer: address, _quorum: u64) {
        // validate if sender already holds an issuer resource
        Transaction::assert(!hasIssuerResource(Transaction::sender()), 42);
        move_to_sender<IssuerResource>(
            newIssuerResource(
                copy _owners, 
                _parent_issuer, 
                _quorum
            )
        );
        EarmarkedProofs::createIssuerLoggedProof(_owners);
    }

    // student use this to register register with Issuer
    public fun initHolder(_issuer: address) acquires IssuerResource{
        Transaction::assert(!hasIssuerResource(Transaction::sender()), 42); // shouldn't be a holder
        Transaction::assert(!Proofs::hasCredentialAccount(Transaction::sender()), 42); // shouldn't hold a credential account
        // TODO : check that the issuer has issuer resource
 
        addHolder(Transaction::sender(), copy _issuer);
        Proofs::newCredentialAccount(_issuer, Transaction::sender());   
    }

    // // requested by sub issuer to register it under its parent issuer
    public fun registerSubIssuer(_owners: vector<address>, parent_issuer: address,  _quorum: u64) acquires IssuerResource{
        let requester_account_ref: &mut IssuerResource;
        Transaction::assert(hasIssuerResource(Transaction::sender()), 42); // only issuer can run this op.

        // update issuer resource and add new holder
        requester_account_ref = borrow_global_mut<IssuerResource>((parent_issuer));
        Vector::push_back<address>(&mut (requester_account_ref).sub_issuers, Transaction::sender());

        registerIssuer(_owners, parent_issuer,  _quorum);
    }

    public fun hasIssuerResource(addr: address): bool {
        exists<IssuerResource>(addr)
    }

    //register holders credential proof in issuer logged proof
    public fun registerHolder(holder:address) acquires IssuerResource{
        let requester_account_mut_ref: &mut IssuerResource;
        let requester_account_ref: & IssuerResource;
        let credential_proof: Proofs::CredentialProof;

        requester_account_mut_ref = borrow_global_mut<IssuerResource>(Transaction::sender());

        // add holder to Issuer resource
        Vector::push_back<address>(
            &mut (requester_account_mut_ref).holders, 
            copy holder
        );

        requester_account_ref = freeze((requester_account_mut_ref));
        credential_proof = Proofs::newCredentialProof(
            Transaction::sender(), 
            holder, 
            *&(requester_account_ref).quorum, 
            *&(requester_account_ref).owners
        );
        
        EarmarkedProofs::registerCP(credential_proof);
    }

    // register holders credential under appropriate credential proof
    public fun registerCredential(holder:address, digest: vector<u8>) acquires IssuerResource{
        let requester_account_ref: &IssuerResource;
        let credential: Proofs::Credential;

        requester_account_ref = borrow_global<IssuerResource>(Transaction::sender());

        credential = Proofs::newCredential(
            holder,
            digest,
            *&(requester_account_ref).owners,
            *&(requester_account_ref).quorum
        );
        
        EarmarkedProofs::registerCredential(credential);
    }

    // // assert that the transaction sender is a valid owner
    public fun canSign(issuer:address): bool acquires IssuerResource{
        let requester_account_ref: &IssuerResource;
        let addr: address;

        addr = Transaction::sender();

        requester_account_ref = borrow_global<IssuerResource>(issuer);
        Vector::contains<address>(&(requester_account_ref).owners, &addr)
    }

    fun newIssuerResource(_owners: vector<address>, parent_issuer: address, _quorum: u64): IssuerResource {
        IssuerResource { 
            owners : (_owners),
            sub_issuers : Vector::empty<address>(),
            parent_issuer : (parent_issuer),
            holders : Vector::empty<address>(),
            digests : Vector::empty<vector<u8>>(),
            revoked_digests : Vector::empty<vector<u8>>(),
            nonce : 1,
            quorum : (_quorum)
        }
    }

    // // adds holder to issuer resource
    fun addHolder(_holder: address, _issuer: address) acquires IssuerResource{
        let requester_account_ref: &mut IssuerResource;
        Transaction::assert(hasIssuerResource(_issuer), 42); // verify issuer

        // update issuer resource and add new holder
        requester_account_ref = borrow_global_mut<IssuerResource>(_issuer);
        Vector::push_back<address>(&mut (requester_account_ref).holders, _holder);
    }
}

// =====================================================
// ====================== SCRIPTS ======================
// =====================================================

// Test that a university can register
//! new-transaction
//! sender: university
use {{bbchain}}::Issuer;
use 0x0::Vector;
use 0x0::Transaction;
fun main() {
    let exists1: bool;
    let existsLoggedProofs: bool;
    let sender: address;
    let owners: vector<address>;

    // check if issuer resource exists
    exists1 = Issuer::hasIssuerResource({{university}});
    Transaction::assert(exists1 == false, 42);
    
    // define owners
    owners = Vector::empty<address>();
    Vector::push_back<address>(&mut owners, {{mathprofessor}});
    Vector::push_back<address>(&mut owners, {{mathevaluator}});
    
    // register issuer with no parent
    Issuer::registerIssuer(
        owners, // _owners
        0x00, // _parent_issuer
        2, // _quorum
    );
    
    // check if issuer resource exists
    sender = Transaction::sender();
    exists1 = Issuer::hasIssuerResource(copy sender);
    Transaction::assert(exists1, 42);

    // check that issuer has logged proof resource
    existsLoggedProofs = Issuer::hasIssuerResource(copy sender);
    Transaction::assert(existsLoggedProofs, 42);
}

// Test that a holder(student) can register in a university
//! new-transaction
//! sender: student1
use {{bbchain}}::Issuer;
use {{bbchain}}::Proofs;
use 0x0::Transaction;
fun main() {
    let exists1: bool;
    // check if issuer resource exists
    exists1 = Proofs::hasCredentialAccount(Transaction::sender());
    Transaction::assert(copy exists1 == false, 42);

    //register to a university
    Issuer::initHolder({{university}});
    
    // check if credential account is created after registration
    exists1 = Proofs::hasCredentialAccount(Transaction::sender());
    Transaction::assert(exists1, 42);
}

// Test that a course can be registered
//! new-transaction
//! sender: mathcourse
use {{bbchain}}::Issuer;
use {{bbchain}}::EarmarkedProofs;
use 0x0::Vector;
use 0x0::Transaction;
fun main() {
    let exists1: bool;
    let existsLoggedProofs: bool;
    let existsRevocationProofs: bool;
    let sender: address;
    let logged_cp_len: u64;
    let has_ownership: bool;
    
    let owners: vector<address>;
    owners = Vector::empty<address>();
    Vector::push_back<address>(&mut owners, {{mathprofessor}});
    Vector::push_back<address>(&mut owners, {{mathevaluator}});

    sender = Transaction::sender();
    exists1 = Issuer::hasIssuerResource(sender);
    Transaction::assert((exists1) == false, 42);

    // check that issuer has logged proof resource
    existsLoggedProofs = EarmarkedProofs::hasLoggedProofs(sender);
    Transaction::assert((existsLoggedProofs) == false, 42);
    
    // register issuer(course) with university as parent
    Issuer::registerIssuer((owners), {{university}}, 2);
    
    // check if issuer resource in earmarked module was created exists
    exists1 = Issuer::hasIssuerResource(copy sender);
    Transaction::assert((exists1), 42);
    existsLoggedProofs = EarmarkedProofs::hasLoggedProofs(copy sender);
    Transaction::assert((existsLoggedProofs), 42);
    existsRevocationProofs = EarmarkedProofs::hasRevocationProofs(copy sender);
    Transaction::assert((existsRevocationProofs), 42);

    // check that the owners are registerd to sign earmarked proofs
    has_ownership = Issuer::hasOwnership({{mathprofessor}}, copy sender);
    Transaction::assert(has_ownership, 123);
    has_ownership = EarmarkedProofs::hasOwnership({{mathprofessor}}, copy sender);
    Transaction::assert(has_ownership, 123);
    has_ownership = Issuer::hasOwnership({{mathevaluator}}, copy sender);
    Transaction::assert(has_ownership, 123);
    has_ownership = EarmarkedProofs::hasOwnership({{mathevaluator}}, copy sender);
    Transaction::assert(has_ownership, 123);

    // register student to course
    Issuer::registerHolder({{student1}});

    // check if a credential proof is registered in earmarked proof
    logged_cp_len = EarmarkedProofs::getCredentialProofLength(sender);
    Transaction::assert((logged_cp_len) == 1, 49);

    
}

// Test that a course can be registered
//! new-transaction
//! sender: anothercourse
use {{bbchain}}::Issuer;
use 0x0::Vector;
fun main() {    
    let owners: vector<address>;
    owners = Vector::empty<address>();
    Vector::push_back<address>(&mut owners, {{mathprofessor}});
    Vector::push_back<address>(&mut owners, {{mathevaluator}});
    
    // register issuer(course) with university as parent
    Issuer::registerIssuer((owners), {{university}}, 2);

    // register student to course
    Issuer::registerHolder({{student1}});
}

// Register Credential for student
//! new-transaction
//! sender: mathcourse
use {{bbchain}}::Issuer;
use {{bbchain}}::EarmarkedProofs;
use 0x0::Transaction;
fun main() {
    let logged_cp_len: u64;
    Issuer::registerCredential({{student1}}, x"00000001") ;
    Issuer::registerCredential({{student1}}, x"00000002") ;
    Issuer::registerCredential({{student1}}, x"00000003") ;

    // check if a credential is registered in earmarked proof
    logged_cp_len = EarmarkedProofs::getCredentialLength({{mathcourse}});
    Transaction::assert((logged_cp_len) == 3, 49);
}

// Register Credential for student
//! new-transaction
//! sender: anothercourse
use {{bbchain}}::Issuer;
use {{bbchain}}::EarmarkedProofs;
use 0x0::Transaction;
fun main() {
    let logged_cp_len: u64;
    Issuer::registerCredential({{student1}}, x"00000004") ;

    // check if a credential is registered in earmarked proof
    logged_cp_len = EarmarkedProofs::getCredentialLength({{anothercourse}});
    Transaction::assert((logged_cp_len) == 1, 49);   
}

// Signing non existent credential should result in error
//! new-transaction
//! sender: mathprofessor
use {{bbchain}}::Issuer;
fun main() {
    Issuer::signCredential({{mathcourse}}, x"0000000100");
    
}
// check: ABORTED

// Signing as non owner result in error
//! new-transaction
//! sender: university
use {{bbchain}}::Issuer;
fun main() {
    Issuer::signCredential({{mathcourse}}, x"00000001");
    
}
// check: ABORTED

// Sign Credential as owner
//! new-transaction
//! sender: mathprofessor
use {{bbchain}}::Issuer;
use {{bbchain}}::EarmarkedProofs;
use 0x0::Transaction;
fun main() {
    let logged_cp_len: u64;
    
    Issuer::signCredential({{mathcourse}}, x"00000001");
    Issuer::signCredential({{mathcourse}}, x"00000002");
    Issuer::signCredential({{mathcourse}}, x"00000003");
    Issuer::signCredential({{anothercourse}}, x"00000004");

    // check if a credential still under credentials
    logged_cp_len = EarmarkedProofs::getCredentialLength({{mathcourse}});
    Transaction::assert((logged_cp_len) == 3, 49);

    logged_cp_len = EarmarkedProofs::getCredentialLength({{anothercourse}});
    Transaction::assert((logged_cp_len) == 1, 49);   
}

// Sign Credential as owner
//! new-transaction
//! sender: mathevaluator
use {{bbchain}}::Issuer;
use {{bbchain}}::EarmarkedProofs;
use 0x0::Transaction;
fun main() {
    let logged_c_len: u64;
    let logged_cp_len: u64;
    
    Issuer::signCredential({{mathcourse}}, x"00000001");
    Issuer::signCredential({{mathcourse}}, x"00000002");
    Issuer::signCredential({{mathcourse}}, x"00000003");

    logged_c_len = EarmarkedProofs::getCredentialLength({{mathcourse}});
    // when quorum has signed the credential should be d to credential proof
    Transaction::assert((logged_c_len) == 0, 49);

    // number of credential proof should still be one, 
    // it is only the credentials that were d to CP when signed by owners
    logged_cp_len = EarmarkedProofs::getCredentialProofLength({{mathcourse}});
    Transaction::assert((logged_cp_len) == 1, 49);
    
}


// Sign Credential as owner
//! new-transaction
//! sender: mathevaluator
use {{bbchain}}::Issuer;
use {{bbchain}}::EarmarkedProofs;
use 0x0::Transaction;
fun main() {
    let logged_c_len: u64;
    let logged_cp_len: u64;
    
    Issuer::signCredential({{anothercourse}}, x"00000004");

    logged_c_len = EarmarkedProofs::getCredentialLength({{anothercourse}});
    // when quorum has signed the credential should be d to credential proof
    Transaction::assert((logged_c_len) == 0, 49);

    // number of credential proof should still be one, 
    // it is only the credentials that were d to CP when signed by owners
    logged_cp_len = EarmarkedProofs::getCredentialProofLength({{anothercourse}});
    Transaction::assert((logged_cp_len) == 1, 49);
    
}


// Test that a holder(student) can claim credential proof
//! new-transaction
//! sender: student1
use {{bbchain}}::EarmarkedProofs;
use {{bbchain}}::Proofs;
use 0x0::Transaction;
fun main() {
    let logged_cp_len: u64;
    let len_cp_credential_account: u64;

    EarmarkedProofs::claimCP({{mathcourse}});

    // number of credential proof should still be one, 
    // it is only the credentials that were d to CP when signed by owners
    logged_cp_len = EarmarkedProofs::getCredentialProofLength({{mathcourse}});
    Transaction::assert((logged_cp_len) == 0, 49);

    // student's credential account should now consist of the signed credential proof
    len_cp_credential_account = Proofs::getCredentialAccountProofLength();
    Transaction::assert((len_cp_credential_account) == 1, 49);
}

// Test that a holder(student) can claim credential proof
//! new-transaction
//! sender: student1
use {{bbchain}}::EarmarkedProofs;
use {{bbchain}}::Proofs;
use 0x0::Transaction;
fun main() {
    let logged_cp_len: u64;
    let len_cp_credential_account: u64;

    EarmarkedProofs::claimCP({{anothercourse}});

    // number of credential proof should still be one, 
    // it is only the credentials that were d to CP when signed by owners
    logged_cp_len = EarmarkedProofs::getCredentialProofLength({{anothercourse}});
    Transaction::assert((logged_cp_len) == 0, 49);

    // student's credential account should now consist of the signed credential proof
    len_cp_credential_account = Proofs::getCredentialAccountProofLength();
    Transaction::assert((len_cp_credential_account) == 2, 49);   
}


// test that a digest can be verified
//! new-transaction
//! sender: verifier
use {{bbchain}}::Issuer;
use {{bbchain}}::Proofs;
use 0x0::Transaction;
use 0x0::Vector;
fun main() {
    let valid_digest: bool;
    let aggregated_digest: vector<u8>;
    let digests: vector<vector<u8>>;

    digests = Vector::empty<vector<u8>>();
    Vector::push_back<vector<u8>>(&mut digests, x"00000001");
    Vector::push_back<vector<u8>>(&mut digests, x"00000002");
    Vector::push_back<vector<u8>>(&mut digests, x"00000003");
    
    aggregated_digest = Proofs::aggregateDigests((digests));
    
    valid_digest = Issuer::verifyCredential((aggregated_digest), {{mathcourse}}, {{student1}} );
    Transaction::assert(valid_digest, 49); 
}

// test that a digest registered for anothercourse can be verified
//! new-transaction
//! sender: verifier
use {{bbchain}}::Issuer;
use 0x0::Transaction;
fun main() {
    let aggregated_digest: vector<u8>;
    
    aggregated_digest = x"00000004";
    
   Transaction::assert( 
       Issuer::verifyCredential((aggregated_digest), {{anothercourse}}, {{student1}}), 
       49
    );
}


// test that a valid digest cant be presented as other holder
//! new-transaction
//! sender: verifier
use {{bbchain}}::Issuer;
use 0x0::Transaction;
fun main() {
    let valid_digest: bool;
    valid_digest = Issuer::verifyCredential(x"00000001", {{mathcourse}}, {{student2}} );
    Transaction::assert(valid_digest == false, 49);   
}

// test that an invalid digest is detected
//! new-transaction
//! sender: verifier
use {{bbchain}}::Issuer;
use 0x0::Transaction;
fun main() {
    let valid_digest: bool;
    valid_digest = Issuer::verifyCredential(x"00000090", {{mathcourse}}, {{student1}} );
    Transaction::assert(valid_digest == false, 49);   
}

// Test that a holder(student) is registered
//! new-transaction
//! sender: student1
use {{bbchain}}::Issuer;
use 0x0::Transaction;
fun main() {
    let has_enrollment: bool;
    has_enrollment = Issuer::hasEnrollment({{student1}}, {{mathcourse}});
    Transaction::assert((has_enrollment), 42);
}

// Test that a university can generate final aggregation for all collected CP
//! new-transaction
//! sender: university
use {{bbchain}}::Issuer;
fun main() {
    Issuer::generateCredentialAccountDigest({{student1}});   
}

// test that a digest can be verified
//! new-transaction
//! sender: verifier
use {{bbchain}}::Issuer;
use {{bbchain}}::Proofs;
use 0x0::Vector;
use 0x0::Transaction;
fun main() {
    let valid_digest: bool;
    let aggregated_digest: vector<u8>;
    let digests: vector<vector<u8>>;

    digests = Vector::empty<vector<u8>>();
    Vector::push_back<vector<u8>>(&mut digests, x"00000001");
    Vector::push_back<vector<u8>>(&mut digests, x"00000002");
    Vector::push_back<vector<u8>>(&mut digests, x"00000003");
    Vector::push_back<vector<u8>>(&mut digests, x"00000004");
    
    aggregated_digest = Proofs::aggregateDigests((digests));
    
    valid_digest = Issuer::verifyCredential((aggregated_digest), {{university}}, {{student1}} );
    Transaction::assert((valid_digest), 49);
    
}


// Test that issuer can revoke digest
//! new-transaction
//! sender: mathcourse
use {{bbchain}}::EarmarkedProofs;
use {{bbchain}}::Proofs;
use 0x0::Vector;
fun main() {
    let aggregated_digest: vector<u8>;
    let digests: vector<vector<u8>>;

    digests = Vector::empty<vector<u8>>();
    Vector::push_back<vector<u8>>(&mut digests, x"00000001");
    Vector::push_back<vector<u8>>(&mut digests, x"00000002");
    Vector::push_back<vector<u8>>(&mut digests, x"00000003");
    
    aggregated_digest = Proofs::aggregateDigests((digests));
    
    EarmarkedProofs::revoke_digest((aggregated_digest));
}

// test that digesst verification now fails
//! new-transaction
//! sender: verifier
use {{bbchain}}::Issuer;
use {{bbchain}}::Proofs;
use 0x0::Vector;
fun main() {
    let aggregated_digest: vector<u8>;
    let digests: vector<vector<u8>>;

    digests = Vector::empty<vector<u8>>();
    Vector::push_back<vector<u8>>(&mut digests, x"00000001");
    Vector::push_back<vector<u8>>(&mut digests, x"00000002");
    Vector::push_back<vector<u8>>(&mut digests, x"00000003");
    
    aggregated_digest = Proofs::aggregateDigests((digests));
    
    // TODO : revoke from credential Account
    Issuer::verifyCredential((aggregated_digest), {{mathcourse}}, {{student1}} );
    
}
// check: ABORTED