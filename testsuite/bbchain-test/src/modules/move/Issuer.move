module Issuer {
    use 0x0000000000000000000000000a550c18::Proofs;
    use 0x0000000000000000000000000a550c18::EarmarkedProofs;
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