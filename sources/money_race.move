module money_race::money_race {

    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::object::UID;
    use sui::tx_context::TxContext;
    use sui::transfer;
    use sui::clock::Clock;

    /* =========================
        CONSTANTS
    ==========================*/

    const STATUS_OPEN: u8 = 0;
    const STATUS_ACTIVE: u8 = 1;
    const STATUS_FINISHED: u8 = 2;

    const E_INVALID_STATUS: u64 = 1;
    const E_NOT_STARTED: u64 = 2;
    const E_PERIOD_INVALID: u64 = 3;
    const E_AMOUNT_INVALID: u64 = 4;
    const E_ALREADY_DEPOSITED: u64 = 5;
    const E_ALREADY_CLAIMED: u64 = 6;
    const E_ZERO_WEIGHT: u64 = 7;
    const E_JOIN_CLOSED: u64 = 8;

    /* =========================
        STRUCTS
    ==========================*/

    public struct AdminCap has key, store {
        id: UID
    }

    public struct Room has key {
        id: UID,
        total_periods: u64,
        deposit_amount: u64,
        strategy_id: u8,
        status: u8,

        start_time_ms: u64,
        period_length_ms: u64,

        total_weight: u64
    }

    public struct Vault has key {
        id: UID,
        principal: Balance<SUI>,
        reward: Balance<SUI>
    }

    public struct PlayerPosition has key, store {
        id: UID,
        owner: address,
        deposited_count: u64,
        last_period: u64,
        reward_claimed: bool,
        principal_claimed: bool // 👈 BARU
    }

    /* =========================
        INIT
    ==========================*/

    fun init(ctx: &mut TxContext) {
        let cap = AdminCap { id: sui::object::new(ctx) };
        transfer::public_transfer(cap, sui::tx_context::sender(ctx));
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    /* =========================
        CREATE ROOM
    ==========================*/

    public fun create_room(
        total_periods: u64,
        deposit_amount: u64,
        strategy_id: u8,
        start_time_ms: u64,
        period_length_ms: u64,
        ctx: &mut TxContext
    ): (Room, Vault) {

        let room = Room {
            id: sui::object::new(ctx),
            total_periods,
            deposit_amount,
            strategy_id,
            status: STATUS_OPEN,
            start_time_ms,
            period_length_ms,
            total_weight: 0
        };

        let vault = Vault {
            id: sui::object::new(ctx),
            principal: balance::zero<SUI>(),
            reward: balance::zero<SUI>()
        };

        (room, vault)
    }

    /* =========================
        TEST HELPERS
    ==========================*/

    #[test_only]
    public fun share_room(room: Room) {
        transfer::share_object(room);
    }

    #[test_only]
    public fun share_vault(vault: Vault) {
        transfer::share_object(vault);
    }

    /* =========================
        START ROOM
    ==========================*/

    public fun start_room(_admin: &AdminCap, room: &mut Room) {
        assert!(room.status == STATUS_OPEN, E_INVALID_STATUS);
        room.status = STATUS_ACTIVE;
    }

    /* =========================
        CURRENT PERIOD
    ==========================*/

    fun current_period(room: &Room, clock: &Clock): u64 {
        let now = sui::clock::timestamp_ms(clock);
        assert!(now >= room.start_time_ms, E_NOT_STARTED);
        (now - room.start_time_ms) / room.period_length_ms
    }

    /* =========================
        JOIN ROOM
    ==========================*/

    public fun join_room(
        room: &Room,
        vault: &mut Vault,
        clock: &Clock,
        coin: Coin<SUI>,
        ctx: &mut TxContext
    ): PlayerPosition {

        assert!(room.status == STATUS_ACTIVE, E_INVALID_STATUS);

        let period = current_period(room, clock);
        assert!(period == 0, E_JOIN_CLOSED);
        assert!(coin::value(&coin) == room.deposit_amount, E_AMOUNT_INVALID);

        let bal = coin::into_balance(coin);
        balance::join(&mut vault.principal, bal);

        PlayerPosition {
            id: sui::object::new(ctx),
            owner: sui::tx_context::sender(ctx),
            deposited_count: 1,
            last_period: 0,
            reward_claimed: false,
            principal_claimed: false
        }
    }

    /* =========================
        DEPOSIT
    ==========================*/

    public fun deposit(
        room: &Room,
        vault: &mut Vault,
        player: &mut PlayerPosition,
        clock: &Clock,
        coin: Coin<SUI>
    ) {
        assert!(room.status == STATUS_ACTIVE, E_INVALID_STATUS);

        let period = current_period(room, clock);
        assert!(period < room.total_periods, E_PERIOD_INVALID);
        assert!(period > player.last_period, E_ALREADY_DEPOSITED);
        assert!(coin::value(&coin) == room.deposit_amount, E_AMOUNT_INVALID);

        let bal = coin::into_balance(coin);
        balance::join(&mut vault.principal, bal);

        player.deposited_count = player.deposited_count + 1;
        player.last_period = period;
    }

    /* =========================
        FINALIZE ROOM
    ==========================*/

    public fun finalize_room(
        _admin: &AdminCap,
        room: &mut Room,
        total_weight: u64
    ) {
        assert!(room.status == STATUS_ACTIVE, E_INVALID_STATUS);
        assert!(total_weight > 0, E_ZERO_WEIGHT);

        room.status = STATUS_FINISHED;
        room.total_weight = total_weight;
    }

    /* =========================
        FUND REWARD
    ==========================*/

    public fun fund_reward_pool(
        _admin: &AdminCap,
        vault: &mut Vault,
        coin: Coin<SUI>
    ) {
        let bal = coin::into_balance(coin);
        balance::join(&mut vault.reward, bal);
    }

    /* =========================
        CLAIM REWARD
    ==========================*/

    public fun claim_reward(
        room: &Room,
        vault: &mut Vault,
        player: &mut PlayerPosition,
        ctx: &mut TxContext
    ) {
        assert!(room.status == STATUS_FINISHED, E_INVALID_STATUS);
        assert!(!player.reward_claimed, E_ALREADY_CLAIMED);

        let reward =
            (player.deposited_count * balance::value(&vault.reward))
            / room.total_weight;

        let bal = balance::split(&mut vault.reward, reward);
        let coin = coin::from_balance(bal, ctx);

        player.reward_claimed = true;
        transfer::public_transfer(coin, player.owner);
    }

    /* =========================
        CLAIM PRINCIPAL (BARU)
    ==========================*/

    public fun claim_principal(
        room: &Room,
        vault: &mut Vault,
        player: &mut PlayerPosition,
        ctx: &mut TxContext
    ) {
        assert!(room.status == STATUS_FINISHED, E_INVALID_STATUS);
        assert!(!player.principal_claimed, E_ALREADY_CLAIMED);

        let amount = player.deposited_count * room.deposit_amount;

        let bal = balance::split(&mut vault.principal, amount);
        let coin = coin::from_balance(bal, ctx);

        player.principal_claimed = true;
        transfer::public_transfer(coin, player.owner);
    }
}
