module mock_usdc::usdc {

    use sui::coin;
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use sui::event;
    use std::option;

    /* =========================
        ERRORS & CONSTANTS
    ==========================*/

    const E_COOLDOWN_NOT_PASSED: u64 = 1;
    const E_AMOUNT_TOO_LARGE: u64 = 2;

    const COOLDOWN_MS: u64 = 86_400_000; // 24 jam
    const MAX_MINT_AMOUNT: u64 = 1_000_000_000; // 1000 USDC (6 decimals)

    /* =========================
        EVENTS
    ==========================*/

    /// Event emitted setiap kali mint berhasil
    public struct MintEvent has copy, drop {
        minter: address,
        amount: u64,
        timestamp_ms: u64,
    }

    /* =========================
        TYPES
    ==========================*/

    /// Marker type
    public struct USDC has drop {}

    /// Shared faucet
    public struct USDCFaucet has key {
        id: UID,
        treasury: coin::TreasuryCap<USDC>,
        last_mint: Table<address, u64>,
    }

    /* =========================
        INIT
    ==========================*/

    fun init(witness: USDC, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency<USDC>(
            witness,
            6,
            b"USDC",
            b"Mock USD Coin",
            b"Mock USDC for testing",
            option::none(),
            ctx
        );

        let faucet = USDCFaucet {
            id: object::new(ctx),
            treasury,
            last_mint: table::new(ctx),
        };

        transfer::share_object(faucet);
        transfer::public_freeze_object(metadata);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        let witness = USDC {};
        init(witness, ctx);
    }

    /* =========================
        MINT (ENTRY)
    ==========================*/

    public entry fun mint(
        faucet: &mut USDCFaucet,
        amount: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(amount <= MAX_MINT_AMOUNT, E_AMOUNT_TOO_LARGE);

        let sender = tx_context::sender(ctx);
        let now = clock::timestamp_ms(clock);

        if (table::contains(&faucet.last_mint, sender)) {
            let last = *table::borrow(&faucet.last_mint, sender);
            assert!(now >= last + COOLDOWN_MS, E_COOLDOWN_NOT_PASSED);
            *table::borrow_mut(&mut faucet.last_mint, sender) = now;
        } else {
            table::add(&mut faucet.last_mint, sender, now);
        };

        let coin = coin::mint(&mut faucet.treasury, amount, ctx);
        transfer::public_transfer(coin, sender);

        /* ===== EMIT EVENT ===== */
        event::emit(MintEvent {
            minter: sender,
            amount,
            timestamp_ms: now,
        });
    }

    /// Mint USDC to a specific recipient address
    /// This is useful for sponsored transactions where the sponsor mints on behalf of a user
    public entry fun mint_to(
        faucet: &mut USDCFaucet,
        recipient: address,
        amount: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(amount <= MAX_MINT_AMOUNT, E_AMOUNT_TOO_LARGE);

        let now = clock::timestamp_ms(clock);

        // Check cooldown for recipient address
        if (table::contains(&faucet.last_mint, recipient)) {
            let last = *table::borrow(&faucet.last_mint, recipient);
            assert!(now >= last + COOLDOWN_MS, E_COOLDOWN_NOT_PASSED);
            *table::borrow_mut(&mut faucet.last_mint, recipient) = now;
        } else {
            table::add(&mut faucet.last_mint, recipient, now);
        };

        let coin = coin::mint(&mut faucet.treasury, amount, ctx);
        transfer::public_transfer(coin, recipient);

        /* ===== EMIT EVENT ===== */
        event::emit(MintEvent {
            minter: recipient,
            amount,
            timestamp_ms: now,
        });
    }

    /* =========================
        VIEW HELPERS (INTERNAL)
    ==========================*/

    public fun time_until_next_mint(
        faucet: &USDCFaucet,
        user: address,
        clock: &Clock,
    ): u64 {
        if (!table::contains(&faucet.last_mint, user)) {
            return 0
        };

        let last = *table::borrow(&faucet.last_mint, user);
        let now = clock::timestamp_ms(clock);
        let next = last + COOLDOWN_MS;

        if (now >= next) 0 else next - now
    }

    public fun can_mint(
        faucet: &USDCFaucet,
        user: address,
        clock: &Clock,
    ): bool {
        time_until_next_mint(faucet, user, clock) == 0
    }
}
