module mock_usdc::usdc {

    use sui::coin;
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};

    /// Error codes
    const E_COOLDOWN_NOT_PASSED: u64 = 1;
    const E_AMOUNT_TOO_LARGE: u64 = 2;

    /// Cooldown period: 24 jam = 24 * 60 * 60 * 1000 ms
    const COOLDOWN_MS: u64 = 86_400_000;

    /// Maximum mint amount per request (1000 USDC)
    const MAX_MINT_AMOUNT: u64 = 1_000_000_000; // 1000 * 10^6 (6 decimals)

    /// Marker type untuk USDC Mock
    public struct USDC has drop {}

    /// Shared object untuk mint USDC dengan cooldown
    public struct USDCFaucet has key {
        id: UID,
        treasury: coin::TreasuryCap<USDC>,
        /// Track last mint time per address
        last_mint: Table<address, u64>,
    }

    /// INIT - Dipanggil saat publish
    fun init(witness: USDC, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency<USDC>(
            witness,
            6,                              // decimals (USDC = 6)
            b"USDC",                        // symbol
            b"Mock USD Coin",               // name
            b"Mock USDC for testing",       // description
            option::none(),                 // icon URL
            ctx
        );

        // Buat faucet sebagai shared object
        let faucet = USDCFaucet {
            id: object::new(ctx),
            treasury: treasury_cap,
            last_mint: table::new(ctx),
        };

        // Share faucet agar semua orang bisa akses
        transfer::share_object(faucet);

        // Freeze metadata (tidak perlu diubah)
        transfer::public_freeze_object(metadata);
    }

    /// MINT USDC dengan cooldown 24 jam
    /// Siapa saja bisa mint, max 1000 USDC per request
    public fun mint(
        faucet: &mut USDCFaucet,
        amount: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): coin::Coin<USDC> {
        // Check amount limit
        assert!(amount <= MAX_MINT_AMOUNT, E_AMOUNT_TOO_LARGE);

        let sender = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        // Check cooldown
        if (table::contains(&faucet.last_mint, sender)) {
            let last_time = *table::borrow(&faucet.last_mint, sender);
            assert!(current_time >= last_time + COOLDOWN_MS, E_COOLDOWN_NOT_PASSED);
            // Update last mint time
            *table::borrow_mut(&mut faucet.last_mint, sender) = current_time;
        } else {
            // First time minting
            table::add(&mut faucet.last_mint, sender, current_time);
        };

        // Mint coin
        coin::mint(&mut faucet.treasury, amount, ctx)
    }

    /// Check berapa lama lagi bisa mint (dalam ms)
    /// Return 0 jika sudah bisa mint
    public fun time_until_next_mint(
        faucet: &USDCFaucet,
        user: address,
        clock: &Clock,
    ): u64 {
        if (!table::contains(&faucet.last_mint, user)) {
            return 0 // Belum pernah mint, bisa mint sekarang
        };

        let last_time = *table::borrow(&faucet.last_mint, user);
        let current_time = clock::timestamp_ms(clock);
        let next_available = last_time + COOLDOWN_MS;

        if (current_time >= next_available) {
            0
        } else {
            next_available - current_time
        }
    }

    /// Check apakah user bisa mint sekarang
    public fun can_mint(
        faucet: &USDCFaucet,
        user: address,
        clock: &Clock,
    ): bool {
        time_until_next_mint(faucet, user, clock) == 0
    }
}
