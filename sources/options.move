module Options::options {
    use std::string::{Self as str, String};
    use std::option::{Self, Option};
    use std::signer::{address_of};
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::table::{Self, Table};

    const USDC_DECIMALS: u64 = 6;

    const ENOT_ADMIN: u64 = 1000;

    const EOPTION_NOT_FOUND: u64 = 2000;

    struct OptionsContractStore<phantom CoinType> has key {
        options: Table<OptionId<CoinType>, OptionsContract<CoinType>>,
    }

    struct OptionId<phantom T> has copy, drop, store {
        // Price feed name
        price_feed: String,
        // Native amount of the underlying per contract
        size: u64,
        // Strike price in native USDC (assuming 6 decimals)
        strike: u64,
        // Expiry unix timestamp
        expiry: u64,
        // Whether the option is a call or put
        call: bool
    }

    // each user has one of these per asset type (eg btc, eth)
    // struct UserOptionsStore<phantom T> has key {
    //     longs: Table<u64, Long>,
    //     short: Table<u64, Long>
    // }

    // struct Long<T> has store {
    //     id: <some way to reference the original contract>,
    //     size: <some way to indicate size of position>
    // }

    // struct Short<T> has store {
    //     id: <some way to reference the original contract>,
    //     size: <some way to indicate size of position>
    // }

    struct OptionsContract<phantom T> has store {
        id: OptionId<T>, // TODO: maybe dont need this
        collateral: Option<Coin<T>>,
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
        let id = OptionId<CoinType> {
            price_feed,
            size,
            strike,
            expiry,
            call,
        };
        let contract = OptionsContract<CoinType> {
            id,
            collateral: option::none(),
            value: option::none(),
        };

        if (exists<OptionsContractStore<CoinType>>(address_of(creator))) {
            let options = &mut borrow_global_mut<OptionsContractStore<CoinType>>(address_of(creator)).options;
            table::add(options, id, contract);
        } else {
            let options = table::new<OptionId<CoinType>, OptionsContract<CoinType>>();
            table::add(&mut options, id, contract);
            let store = OptionsContractStore<CoinType> {
                options
            };
            move_to(creator, store);
        }
    }

    public entry fun mint<C>(contract: &mut OptionsContract<C>, collateral: Coin<C>) {
        let _num_tokens = aptos_framework::coin::value<C>(&collateral) / contract.id.size;
        if (option::is_none(&contract.collateral)) {
            option::fill(&mut contract.collateral, collateral);
        } else {
            let coins = option::borrow_mut(&mut contract.collateral);
            coin::merge(coins, collateral);
        }
        // merge the coin
        // issue a corresponding long/short tokens

    }

    // public entry fun get_contract<C>(
    //     user: address,
    //     size: u64,
    //     strike: u64,
    //     expiry: u64,
    //     call: bool
    // ): &OptionsContract<C> acquires OptionsContractStore {
    //     let options = &borrow_global<OptionsContractStore<C>>(user).options;
    //     let i = 0;
    //     while (i < vector::length(options)) {
    //         let option = vector::borrow(options, i);
    //         if (option.size == size && option.strike == strike && option.expiry == expiry && option.call == call) {
    //             return option
    //         };
    //         i = i + 1;
    //     };
    //     abort EOPTION_NOT_FOUND
    // }

    struct ManagedCoin {}
    struct WrappedBTCCoin {}
    
    #[test(admin = @Options)]
    fun test_contract(admin: &signer) acquires OptionsContractStore {
        create_contract<ManagedCoin>(admin, str::utf8(b"test"), 1000, 1000, 10000000000000, true);
        create_contract<ManagedCoin>(admin, str::utf8(b"test"), 1000, 2000, 10000000000000, true);
        create_contract<WrappedBTCCoin>(admin, str::utf8(b"btc"), 1000, 1000, 10000000000000, true);

        let managed_store = borrow_global<OptionsContractStore<ManagedCoin>>(address_of(admin));
        assert!(table::length<OptionId<ManagedCoin>, OptionsContract<ManagedCoin>>(&managed_store.options) == 2, 1000);

        // if you do it without the & it's an implicit copy, tries to drop too
        let btc_store = &borrow_global<OptionsContractStore<WrappedBTCCoin>>(address_of(admin)).options;
        assert!(table::length<OptionId<WrappedBTCCoin>, OptionsContract<WrappedBTCCoin>>(btc_store) == 1, 1000);
    }

    #[test(admin = @Options)]
    fun test_mint(admin: &signer) acquires OptionsContractStore {
        let price_feed = str::utf8(b"test");
        let size: u64 = 1000;
        let strike: u64 = 1000;
        let expiry: u64 = 10000000000000;
        let is_call = true;
        let id = OptionId<ManagedCoin> {
            price_feed,
            size,
            strike,
            expiry,
            call: is_call
        };
        create_contract<ManagedCoin>(admin, price_feed, size, strike, expiry, is_call);

        let _contract = table::borrow(&borrow_global<OptionsContractStore<ManagedCoin>>(address_of(admin)).options, id);
        
    }
}