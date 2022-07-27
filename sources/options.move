module Options::options {
    use std::string::{Self as str, String};
    use std::option::{Self, Option};
    use std::signer::{address_of};
    use std::vector::{Self};
    use aptos_framework::coin::{Coin};

    const USDC_DECIMALS: u64 = 6;

    const ENOT_ADMIN: u64 = 1000;

    struct OptionsContractStore<phantom CoinType> has key {
        options: vector<OptionsContract<CoinType>>,
    }

    // Each user can only have 1 OptionsContract object at a time. 
    // Account -> (object type = store) -> data

    struct OptionsContract<phantom CoinType> has store {
        collateral: Option<Coin<CoinType>>,
        // Price feed name
        price_feed: String,
        // Native amount of the underlying per contract
        size: u64,
        // Strike price in native USDC (assuming 6 decimals)
        strike: u64,
        // Expiry unix timestamp
        expiry: u64,
        // Whether the option is a call or put
        call: bool,
        // Value per contract at expiry, denominated in native collateral quantity
        value: Option<u64>,
    }

    public entry fun create_contract<CoinType>(
        creator: &signer,
        price_feed: String,
        size: u64,
        strike: u64,
        expiry: u64,
        call: bool
    ) acquires OptionsContractStore {
        assert!(address_of(creator) == @Options, ENOT_ADMIN);
        let contract = OptionsContract<CoinType> {
            collateral: option::none(),
            price_feed,
            size,
            strike,
            expiry,
            call,
            value: option::none(), 
        };

        if (exists<OptionsContractStore<CoinType>>(address_of(creator))) {
            let options = &mut borrow_global_mut<OptionsContractStore<CoinType>>(address_of(creator)).options;
            std::vector::push_back(options, contract);
        } else {
            let options = OptionsContractStore<CoinType> {
                options: std::vector::singleton(contract)
            };
            move_to(creator, options);
        }
    }

    // public entry fun mint<C>(contract: OptionsContract<C>, collateral: Coin<C>) {
    //     // let options = &mut borrow_global_mut<OptionsContractStore<C>>(address_of(@Options)).options;
    //     // scan for match, then write  if we find one. 

    //     let num_tokens = aptos_framework::coin::value<C>(&collateral) / contract.size;
    //     if (option::is_none(&contract.collateral)) {
    //         option::fill(&mut contract.collateral, collateral);
    //     } else {
    //         let coins = option::borrow_mut(&mut contract.collateral);
    //         coin::merge(coins, collateral);
    //     }
    //     // merge the coin
    //     // issue a corresponding long/short tokens

    // }

    // public entry fun get_contracts<C>(user: address): vector<OptionsContract<C>> acquires OptionsContractStore {
    //     let value = borrow_global<OptionsContractStore<C>>(user).options;
    //     value
    // }

    struct ManagedCoin {}
    struct WrappedBTCCoin {}
    
    #[test(admin = @Options)]
    fun test_contract(admin: &signer) acquires OptionsContractStore {
        create_contract<ManagedCoin>(admin, str::utf8(b"test"), 1000, 1000, 10000000000000, true);
        create_contract<ManagedCoin>(admin, str::utf8(b"test"), 1000, 2000, 10000000000000, true);
        create_contract<WrappedBTCCoin>(admin, str::utf8(b"btc"), 1000, 1000, 10000000000000, true);

        let managed_store = borrow_global<OptionsContractStore<ManagedCoin>>(address_of(admin));
        assert!(vector::length(&managed_store.options) == 2, 1000);

        // if you do it without the & it's an implicit copy, tries to drop too
        let btc_store = &borrow_global<OptionsContractStore<WrappedBTCCoin>>(address_of(admin)).options;
        assert!(vector::length(btc_store) == 1, 1000);
    }

    #[test(admin = @Options)]
    fun test_mint(admin: &signer) acquires OptionsContractStore {
        create_contract<ManagedCoin>(admin, str::utf8(b"test"), 1000, 1000, 10000000000000, true);
    }
}