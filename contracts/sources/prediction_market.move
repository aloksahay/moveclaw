/// MoveClaw Prediction Market - Binary outcome markets resolved by AI agent
module moveclaw::prediction_market {
    use std::signer;
    use std::string::String;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::timestamp;
    use aptos_framework::account;
    use aptos_framework::event;
    use aptos_std::table::{Self, Table};

    // ── Errors ──────────────────────────────────────────────────────────
    const E_MARKET_NOT_FOUND: u64 = 1;
    const E_MARKET_ALREADY_RESOLVED: u64 = 2;
    const E_MARKET_NOT_RESOLVED: u64 = 3;
    const E_NOT_CREATOR: u64 = 4;
    const E_NO_POSITION: u64 = 5;
    const E_ZERO_AMOUNT: u64 = 6;
    const E_ALREADY_CLAIMED: u64 = 7;
    const E_REGISTRY_EXISTS: u64 = 8;
    const E_REGISTRY_NOT_FOUND: u64 = 9;
    const E_WRONG_OUTCOME: u64 = 10;

    // ── Data structures ─────────────────────────────────────────────────
    struct Market has store, copy, drop {
        market_id: u64,
        question: String,
        creator: address,
        yes_pool: u64,
        no_pool: u64,
        resolved: bool,
        outcome: bool,
        created_at: u64,
        resolve_after: u64,
    }

    struct Position has key, store, drop {
        market_id: u64,
        is_yes: bool,
        amount: u64,
        claimed: bool,
    }

    struct MarketRegistry has key {
        next_market_id: u64,
        markets: Table<u64, Market>,
        market_created_events: event::EventHandle<MarketCreatedEvent>,
        market_resolved_events: event::EventHandle<MarketResolvedEvent>,
    }

    // ── Events ──────────────────────────────────────────────────────────
    struct MarketCreatedEvent has drop, store {
        market_id: u64,
        question: String,
        creator: address,
        resolve_after: u64,
    }

    struct MarketResolvedEvent has drop, store {
        market_id: u64,
        outcome: bool,
    }

    // ── Resource account for holding market funds ───────────────────────
    struct MarketEscrow has key {
        dummy: bool,
    }

    // ── Init: creator calls this once to set up the registry ───────────
    public entry fun init_registry(creator: &signer) {
        let addr = signer::address_of(creator);
        assert!(!exists<MarketRegistry>(addr), E_REGISTRY_EXISTS);
        move_to(creator, MarketRegistry {
            next_market_id: 1,
            markets: table::new(),
            market_created_events: account::new_event_handle<MarketCreatedEvent>(creator),
            market_resolved_events: account::new_event_handle<MarketResolvedEvent>(creator),
        });
    }

    // ── Create a new prediction market ─────────────────────────────────
    public entry fun create_market(
        creator: &signer,
        question: String,
        resolve_after_secs: u64,
    ) acquires MarketRegistry {
        let creator_addr = signer::address_of(creator);

        // Auto-init registry if not present
        if (!exists<MarketRegistry>(creator_addr)) {
            init_registry(creator);
        };

        let registry = borrow_global_mut<MarketRegistry>(creator_addr);
        let market_id = registry.next_market_id;
        let now = timestamp::now_seconds();

        let market = Market {
            market_id,
            question: copy question,
            creator: creator_addr,
            yes_pool: 0,
            no_pool: 0,
            resolved: false,
            outcome: false,
            created_at: now,
            resolve_after: now + resolve_after_secs,
        };

        table::add(&mut registry.markets, market_id, market);
        registry.next_market_id = market_id + 1;

        event::emit_event(&mut registry.market_created_events, MarketCreatedEvent {
            market_id,
            question,
            creator: creator_addr,
            resolve_after: now + resolve_after_secs,
        });
    }

    // ── Place a bet on a market ────────────────────────────────────────
    public entry fun place_bet(
        bettor: &signer,
        registry_addr: address,
        market_id: u64,
        is_yes: bool,
        amount: u64,
    ) acquires MarketRegistry {
        assert!(amount > 0, E_ZERO_AMOUNT);
        assert!(exists<MarketRegistry>(registry_addr), E_REGISTRY_NOT_FOUND);

        let registry = borrow_global_mut<MarketRegistry>(registry_addr);
        assert!(table::contains(&registry.markets, market_id), E_MARKET_NOT_FOUND);

        let market = table::borrow_mut(&mut registry.markets, market_id);
        assert!(!market.resolved, E_MARKET_ALREADY_RESOLVED);

        // Transfer coins from bettor to registry address (escrow)
        coin::transfer<AptosCoin>(bettor, registry_addr, amount);

        // Update pool
        if (is_yes) {
            market.yes_pool = market.yes_pool + amount;
        } else {
            market.no_pool = market.no_pool + amount;
        };

        // Store position under bettor's address
        // For simplicity, one position per market per user
        // In a real app you'd use a Table<u64, Position> under each user
        move_to(bettor, Position {
            market_id,
            is_yes,
            amount,
            claimed: false,
        });
    }

    // ── Resolve a market (only creator can resolve) ────────────────────
    public entry fun resolve_market(
        resolver: &signer,
        market_id: u64,
        outcome: bool,
    ) acquires MarketRegistry {
        let resolver_addr = signer::address_of(resolver);
        assert!(exists<MarketRegistry>(resolver_addr), E_REGISTRY_NOT_FOUND);

        let registry = borrow_global_mut<MarketRegistry>(resolver_addr);
        assert!(table::contains(&registry.markets, market_id), E_MARKET_NOT_FOUND);

        let market = table::borrow_mut(&mut registry.markets, market_id);
        assert!(!market.resolved, E_MARKET_ALREADY_RESOLVED);
        assert!(market.creator == resolver_addr, E_NOT_CREATOR);

        market.resolved = true;
        market.outcome = outcome;

        event::emit_event(&mut registry.market_resolved_events, MarketResolvedEvent {
            market_id,
            outcome,
        });
    }

    // ── Pay winner — called by the market creator (AI agent) who holds escrow funds
    public entry fun pay_winner(
        creator: &signer,
        winner: address,
        market_id: u64,
        amount: u64,
    ) acquires MarketRegistry, Position {
        let creator_addr = signer::address_of(creator);
        assert!(exists<MarketRegistry>(creator_addr), E_REGISTRY_NOT_FOUND);

        let registry = borrow_global<MarketRegistry>(creator_addr);
        assert!(table::contains(&registry.markets, market_id), E_MARKET_NOT_FOUND);

        let market = table::borrow(&registry.markets, market_id);
        assert!(market.resolved, E_MARKET_NOT_RESOLVED);
        assert!(market.creator == creator_addr, E_NOT_CREATOR);

        // Verify winner has a matching position
        assert!(exists<Position>(winner), E_NO_POSITION);
        let position = borrow_global_mut<Position>(winner);
        assert!(position.market_id == market_id, E_NO_POSITION);
        assert!(!position.claimed, E_ALREADY_CLAIMED);
        assert!(position.is_yes == market.outcome, E_WRONG_OUTCOME);

        position.claimed = true;

        // Creator transfers escrowed funds to the winner
        if (amount > 0) {
            coin::transfer<AptosCoin>(creator, winner, amount);
        };
    }

    // ── View functions ─────────────────────────────────────────────────
    #[view]
    public fun get_market(
        registry_addr: address,
        market_id: u64,
    ): (String, u64, u64, bool, bool) acquires MarketRegistry {
        assert!(exists<MarketRegistry>(registry_addr), E_REGISTRY_NOT_FOUND);
        let registry = borrow_global<MarketRegistry>(registry_addr);
        assert!(table::contains(&registry.markets, market_id), E_MARKET_NOT_FOUND);
        let market = table::borrow(&registry.markets, market_id);
        (market.question, market.yes_pool, market.no_pool, market.resolved, market.outcome)
    }

    #[view]
    public fun get_position(
        addr: address,
        market_id: u64,
    ): (bool, u64) acquires Position {
        assert!(exists<Position>(addr), E_NO_POSITION);
        let position = borrow_global<Position>(addr);
        assert!(position.market_id == market_id, E_NO_POSITION);
        (position.is_yes, position.amount)
    }

    #[view]
    public fun get_next_market_id(registry_addr: address): u64 acquires MarketRegistry {
        assert!(exists<MarketRegistry>(registry_addr), E_REGISTRY_NOT_FOUND);
        borrow_global<MarketRegistry>(registry_addr).next_market_id
    }

    // ── Tests ──────────────────────────────────────────────────────────
    #[test(creator = @moveclaw, framework = @aptos_framework)]
    public fun test_create_market(creator: &signer, framework: &signer) acquires MarketRegistry {
        // Setup
        account::create_account_for_test(signer::address_of(creator));
        timestamp::set_time_has_started_for_testing(framework);

        // Create market
        create_market(creator, std::string::utf8(b"Will BTC hit 100k?"), 60);

        // Verify
        let creator_addr = signer::address_of(creator);
        let (question, yes_pool, no_pool, resolved, _outcome) = get_market(creator_addr, 1);
        assert!(question == std::string::utf8(b"Will BTC hit 100k?"), 0);
        assert!(yes_pool == 0, 1);
        assert!(no_pool == 0, 2);
        assert!(!resolved, 3);
    }

    #[test(creator = @moveclaw, framework = @aptos_framework)]
    public fun test_resolve_market(creator: &signer, framework: &signer) acquires MarketRegistry {
        account::create_account_for_test(signer::address_of(creator));
        timestamp::set_time_has_started_for_testing(framework);

        create_market(creator, std::string::utf8(b"Test?"), 60);
        resolve_market(creator, 1, true);

        let creator_addr = signer::address_of(creator);
        let (_q, _y, _n, resolved, outcome) = get_market(creator_addr, 1);
        assert!(resolved, 0);
        assert!(outcome, 1);
    }
}
