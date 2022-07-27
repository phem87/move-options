// TODO: enforce that strike is usdc

module Options::options {
    use std::string::{Self as str, String};
    use std::option::{Self, Option};
    use std::signer::{address_of};
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::table::{Self, Table};
    use std::vector::{Self};

    const USDC_DECIMALS: u64 = 6;

    const ENOT_ADMIN: u64 = 1000;

    const EADMIN_STORE_EXISTS: u64= 2000;
    const EUSER_STORE_EXISTS: u64= 2001;

    const EOPTION_NOT_FOUND: u64 = 3000;
    const EINVALID_BURN: u64 = 3001;

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

    struct OptionsContract<phantom T> has store {
        id: OptionId<T>, // TODO: maybe dont need this
        collateral: Option<Coin<T>>,
        // Value per contract at expiry, denominated in native collateral quantity
        value: Option<u64>,
    }

    // each user has one of these per underlying asset type (eg btc, eth, usdc)
    struct UserOptionsStore<phantom T> has key {
        longs: vector<Long<T>>,
        shorts: vector<Short<T>>
    }

    struct Long<phantom T> has store {
        id: OptionId<T>,
        // number of options
        quantity: u64,
    }

    struct Short<phantom T> has store {
        id: OptionId<T>,
        // number of options
        quantity: u64,
    }

    public entry fun init_user_store<T>(user: &signer) {
        assert!(!exists<UserOptionsStore<T>>(address_of(user)), EUSER_STORE_EXISTS);
        let store = UserOptionsStore<T> {
            longs: vector::empty<Long<T>>(),
            shorts: vector::empty<Short<T>>()
        };
        move_to(user, store);
    }

    fun add_to_user_store<T>(user: &signer, long: Long<T>, short: Short<T>) acquires UserOptionsStore {
        let store = borrow_global_mut<UserOptionsStore<T>>(address_of(user));
        vector::push_back(&mut store.longs, long);
        vector::push_back(&mut store.shorts, short);
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

    public entry fun mint<C>(
        writer: &signer,
        contract: &mut OptionsContract<C>,
        collateral: Coin<C>
    ) acquires UserOptionsStore {
        // TODO: assert that it divides evenly
        let num_tokens = aptos_framework::coin::value<C>(&collateral) / contract.id.size;
        if (option::is_none(&contract.collateral)) {
            option::fill(&mut contract.collateral, collateral);
        } else {
            let coins = option::borrow_mut(&mut contract.collateral);
            coin::merge(coins, collateral);
        };
        // merge the coin
        // issue a corresponding long/short tokens
        let long = Long<C> {
            id: contract.id,
            quantity: num_tokens,
        };
        let short = Short<C> {
            id: contract.id,
            quantity: num_tokens,
        };
        if (!exists<UserOptionsStore<C>>(address_of(writer))) {
            init_user_store<C>(writer);
        };
        add_to_user_store(writer, long, short);
    }

    // public fun ids_equal<C>

    /// 
    public entry fun burn<C>(
        _user: &signer,
        contract: &mut OptionsContract<C>,
        long_token: Long<C>,
        short_token: Short<C>
    ): Coin<C> {
        // unpack to destroy
        let Long<C> { id: long_id, quantity: long_quantity } = long_token;
        let Short<C> { id: short_id, quantity: short_quantity } = short_token;

        assert!(long_id == contract.id, EINVALID_BURN);
        assert!(long_id == short_id, EINVALID_BURN);
        assert!(long_quantity == short_quantity, EINVALID_BURN);

        // amount of underlying
        let redemption_quantity = contract.id.size * long_quantity;
        coin::extract(option::borrow_mut(&mut contract.collateral), redemption_quantity)
        // send redemption_quantity of the underlying back to the user
        // burn the long and the short
    }

    // No oracle yet so will just have admin set a price
    public entry fun settle<C>(
        admin: &signer,
        contract: &mut OptionsContract<C>,
        _price: u64
    ) {
        assert!(address_of(admin) == @Options, ENOT_ADMIN);
        contract.value = option::some(0);
    }

    public entry fun exercise<C>(
        _user: &signer,
        contract: &mut OptionsContract<C>,
        long: Long<C>,
    ) {
       let value = *option::borrow(&contract.value);
       let Long<C> { id: long_id, quantity: long_quantity } = long;
       assert!(long_id == contract.id, EINVALID_BURN); 
       let _exercise_value = value * long_quantity; 
       // send that underlying back if > 0
    }

    public entry fun redeem<C>(
        _user: &signer,
        contract: &mut OptionsContract<C>,
        short: Short<C>,
    ) {
        let value = *option::borrow(&contract.value);
        let Short<C> { id: short_id, quantity: short_quantity } = short;
        assert!(short_id == contract.id, EINVALID_BURN); 
        let _redemption_value = if (value > 0) {
            (contract.id.size - value) * short_quantity
        } else {
            0
        };
       // send that underlying back if > 0
    }
    
    #[test_only]
    struct ManagedCoin {}
    #[test_only]
    struct WrappedBTCCoin {}

    #[test_only]
    struct Caps<phantom T> {
        m: coin::MintCapability<T>,
        b: coin::BurnCapability<T>,
    }

    #[test_only]
    struct Fixture {
        managed_caps: Caps<ManagedCoin>,
    }

    #[test_only]
    fun setup(account: &signer): Fixture {
        let name = str::utf8(b"MNG");
        let (m, b) = coin::initialize<ManagedCoin>(account, name, name, 3, true);
        let managed_caps = Caps { m, b };
        Fixture {
            managed_caps,
        }
    }

    #[test_only]
    fun destroy_caps<T>(c: Caps<T>) {
        let Caps { m, b } = c;
        coin::destroy_mint_cap<T>(m);
        coin::destroy_burn_cap<T>(b);
    }

    #[test_only]
    fun teardown(fix: Fixture) {
        let Fixture { managed_caps } = fix;
        destroy_caps(managed_caps);
    }
    
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

    #[test(admin = @Options, writer = @0x0fac75)]
    fun test_mint(admin: &signer, writer: &signer) acquires OptionsContractStore, UserOptionsStore {
        let fix = setup(admin);
        let price_feed = str::utf8(b"test");
        let size: u64 = 1000;
        let strike: u64 = 5000000;
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

        let managed_coin = coin::mint<ManagedCoin>(size, &fix.managed_caps.m);
        let host_store = &mut borrow_global_mut<OptionsContractStore<ManagedCoin>>(address_of(admin)).options;
        let contract = table::borrow_mut<OptionId<ManagedCoin>, OptionsContract<ManagedCoin>>(host_store, id);
        mint<ManagedCoin>(writer, contract, managed_coin);
        teardown(fix);
    }

    #[test(admin = @Options, writer = @0x0fac75)]
    fun test_burn(admin: &signer, writer: &signer) acquires OptionsContractStore, UserOptionsStore {
        let fix = setup(admin);
        let price_feed = str::utf8(b"test");
        let size: u64 = 1000;
        let strike: u64 = 5000000;
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

        let managed_coin = coin::mint<ManagedCoin>(size, &fix.managed_caps.m);
        let host_store = &mut borrow_global_mut<OptionsContractStore<ManagedCoin>>(address_of(admin)).options;
        let contract = table::borrow_mut<OptionId<ManagedCoin>, OptionsContract<ManagedCoin>>(host_store, id);
        mint<ManagedCoin>(writer, contract, managed_coin);

        let user_options_store = borrow_global_mut<UserOptionsStore<ManagedCoin>>(address_of(writer));
        let long = vector::remove(&mut user_options_store.longs, 0);
        let short = vector::remove(&mut user_options_store.shorts, 0);

        let collateral = burn(writer, contract, long, short);
        assert!(coin::value(&collateral) == size, 6);
        coin::burn(collateral, &fix.managed_caps.b);
        teardown(fix);
    }

    // #[test(admin = @Options, writer = @0x0fac75)]
    // fun test_exercise(admin: &signer, writer: &signer) acquires OptionsContractStore, UserOptionsStore {

    // }

    // #[test(admin = @Options, writer = @0x0fac75)]
    // fun test_redeem(admin: &signer, writer: &signer) acquires OptionsContractStore, UserOptionsStore {

    // }

}