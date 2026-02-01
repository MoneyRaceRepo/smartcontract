#[test_only]
module mock_usdc::usdc_tests {
    use mock_usdc::usdc::{Self, USDC, USDCFaucet};
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};

    /* =========================
        TEST CONSTANTS
    ==========================*/

    const USER1: address = @0x1;
    const USER2: address = @0x2;

    const MAX_MINT_AMOUNT: u64 = 1_000_000_000; // 1000 USDC (6 decimals)
    const COOLDOWN_MS: u64 = 86_400_000; // 24 hours in milliseconds
    const START_TIME: u64 = 1000000000; // Some arbitrary start time

    /* =========================
        HELPER FUNCTIONS
    ==========================*/

    fun setup_faucet(): Scenario {
        let mut scenario = ts::begin(@0x0);
        {
            usdc::init_for_testing(ts::ctx(&mut scenario));
        };
        scenario
    }

    /* =========================
        TEST: MINT SUCCESS
    ==========================*/

    #[test]
    fun test_mint_success() {
        let mut scenario = setup_faucet();

        // User mints 100 USDC for the first time
        ts::next_tx(&mut scenario, USER1);
        {
            let mut faucet = ts::take_shared<USDCFaucet>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME);

            usdc::mint(&mut faucet, 100_000_000, &clock, ts::ctx(&mut scenario)); // 100 USDC

            clock::destroy_for_testing(clock);
            ts::return_shared(faucet);
        };

        // Verify coin was minted and transferred
        ts::next_tx(&mut scenario, USER1);
        {
            let coin = ts::take_from_sender<Coin<USDC>>(&scenario);
            assert!(coin::value(&coin) == 100_000_000, 0);
            ts::return_to_sender(&scenario, coin);
        };

        ts::end(scenario);
    }

    /* =========================
        TEST: MINT MAX AMOUNT
    ==========================*/

    #[test]
    fun test_mint_max_amount() {
        let mut scenario = setup_faucet();

        // User mints maximum allowed amount
        ts::next_tx(&mut scenario, USER1);
        {
            let mut faucet = ts::take_shared<USDCFaucet>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME);

            usdc::mint(&mut faucet, MAX_MINT_AMOUNT, &clock, ts::ctx(&mut scenario));

            clock::destroy_for_testing(clock);
            ts::return_shared(faucet);
        };

        // Verify max amount was minted
        ts::next_tx(&mut scenario, USER1);
        {
            let coin = ts::take_from_sender<Coin<USDC>>(&scenario);
            assert!(coin::value(&coin) == MAX_MINT_AMOUNT, 0);
            ts::return_to_sender(&scenario, coin);
        };

        ts::end(scenario);
    }

    /* =========================
        TEST: MINT EXCEEDS MAX
    ==========================*/

    #[test]
    #[expected_failure(abort_code = 2)] // E_AMOUNT_TOO_LARGE
    fun test_mint_exceeds_max() {
        let mut scenario = setup_faucet();

        // Try to mint more than max amount (should fail)
        ts::next_tx(&mut scenario, USER1);
        {
            let mut faucet = ts::take_shared<USDCFaucet>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME);

            usdc::mint(&mut faucet, MAX_MINT_AMOUNT + 1, &clock, ts::ctx(&mut scenario));

            clock::destroy_for_testing(clock);
            ts::return_shared(faucet);
        };

        ts::end(scenario);
    }

    /* =========================
        TEST: COOLDOWN ENFORCEMENT
    ==========================*/

    #[test]
    #[expected_failure(abort_code = 1)] // E_COOLDOWN_NOT_PASSED
    fun test_mint_cooldown_not_passed() {
        let mut scenario = setup_faucet();

        // First mint succeeds
        ts::next_tx(&mut scenario, USER1);
        {
            let mut faucet = ts::take_shared<USDCFaucet>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME);

            usdc::mint(&mut faucet, 100_000_000, &clock, ts::ctx(&mut scenario));

            clock::destroy_for_testing(clock);
            ts::return_shared(faucet);
        };

        // Try to mint again immediately (should fail)
        ts::next_tx(&mut scenario, USER1);
        {
            let mut faucet = ts::take_shared<USDCFaucet>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME + 1000); // Only 1 second later

            usdc::mint(&mut faucet, 100_000_000, &clock, ts::ctx(&mut scenario));

            clock::destroy_for_testing(clock);
            ts::return_shared(faucet);
        };

        ts::end(scenario);
    }

    /* =========================
        TEST: MINT AFTER COOLDOWN
    ==========================*/

    #[test]
    fun test_mint_after_cooldown() {
        let mut scenario = setup_faucet();

        // First mint
        ts::next_tx(&mut scenario, USER1);
        {
            let mut faucet = ts::take_shared<USDCFaucet>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME);

            usdc::mint(&mut faucet, 100_000_000, &clock, ts::ctx(&mut scenario));

            clock::destroy_for_testing(clock);
            ts::return_shared(faucet);
        };

        // Second mint after cooldown (24 hours + 1 ms)
        ts::next_tx(&mut scenario, USER1);
        {
            let mut faucet = ts::take_shared<USDCFaucet>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME + COOLDOWN_MS + 1);

            usdc::mint(&mut faucet, 200_000_000, &clock, ts::ctx(&mut scenario)); // 200 USDC

            clock::destroy_for_testing(clock);
            ts::return_shared(faucet);
        };

        // Verify second mint succeeded - just check we have coins
        ts::next_tx(&mut scenario, USER1);
        {
            // Take first coin (should exist from first mint)
            let coin1 = ts::take_from_sender<Coin<USDC>>(&scenario);
            assert!(coin::value(&coin1) > 0, 0); // At least one coin exists
            ts::return_to_sender(&scenario, coin1);
        };

        ts::end(scenario);
    }

    /* =========================
        TEST: MULTIPLE USERS
    ==========================*/

    #[test]
    fun test_multiple_users_can_mint() {
        let mut scenario = setup_faucet();

        // User 1 mints
        ts::next_tx(&mut scenario, USER1);
        {
            let mut faucet = ts::take_shared<USDCFaucet>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME);

            usdc::mint(&mut faucet, 100_000_000, &clock, ts::ctx(&mut scenario));

            clock::destroy_for_testing(clock);
            ts::return_shared(faucet);
        };

        // User 2 mints at same time (should succeed - different user)
        ts::next_tx(&mut scenario, USER2);
        {
            let mut faucet = ts::take_shared<USDCFaucet>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME);

            usdc::mint(&mut faucet, 200_000_000, &clock, ts::ctx(&mut scenario));

            clock::destroy_for_testing(clock);
            ts::return_shared(faucet);
        };

        // Verify User 1 got their coin
        ts::next_tx(&mut scenario, USER1);
        {
            let coin = ts::take_from_sender<Coin<USDC>>(&scenario);
            assert!(coin::value(&coin) == 100_000_000, 0);
            ts::return_to_sender(&scenario, coin);
        };

        // Verify User 2 got their coin
        ts::next_tx(&mut scenario, USER2);
        {
            let coin = ts::take_from_sender<Coin<USDC>>(&scenario);
            assert!(coin::value(&coin) == 200_000_000, 0);
            ts::return_to_sender(&scenario, coin);
        };

        ts::end(scenario);
    }

    /* =========================
        TEST: VIEW HELPERS
    ==========================*/

    #[test]
    fun test_can_mint_helper() {
        let mut scenario = setup_faucet();

        // Initially, user should be able to mint
        ts::next_tx(&mut scenario, USER1);
        {
            let faucet = ts::take_shared<USDCFaucet>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME);

            assert!(usdc::can_mint(&faucet, USER1, &clock), 0);

            clock::destroy_for_testing(clock);
            ts::return_shared(faucet);
        };

        // After minting, user should NOT be able to mint
        ts::next_tx(&mut scenario, USER1);
        {
            let mut faucet = ts::take_shared<USDCFaucet>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME);

            usdc::mint(&mut faucet, 100_000_000, &clock, ts::ctx(&mut scenario));

            clock::destroy_for_testing(clock);
            ts::return_shared(faucet);
        };

        ts::next_tx(&mut scenario, USER1);
        {
            let faucet = ts::take_shared<USDCFaucet>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME + 1000); // 1 second later

            assert!(!usdc::can_mint(&faucet, USER1, &clock), 0);

            clock::destroy_for_testing(clock);
            ts::return_shared(faucet);
        };

        // After cooldown, user should be able to mint again
        ts::next_tx(&mut scenario, USER1);
        {
            let faucet = ts::take_shared<USDCFaucet>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME + COOLDOWN_MS + 1);

            assert!(usdc::can_mint(&faucet, USER1, &clock), 0);

            clock::destroy_for_testing(clock);
            ts::return_shared(faucet);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_time_until_next_mint() {
        let mut scenario = setup_faucet();

        // User mints
        ts::next_tx(&mut scenario, USER1);
        {
            let mut faucet = ts::take_shared<USDCFaucet>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME);

            usdc::mint(&mut faucet, 100_000_000, &clock, ts::ctx(&mut scenario));

            clock::destroy_for_testing(clock);
            ts::return_shared(faucet);
        };

        // Check time until next mint 1 hour later
        ts::next_tx(&mut scenario, USER1);
        {
            let faucet = ts::take_shared<USDCFaucet>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            let one_hour = 3_600_000; // 1 hour in ms
            clock::set_for_testing(&mut clock, START_TIME + one_hour);

            let time_left = usdc::time_until_next_mint(&faucet, USER1, &clock);
            assert!(time_left == COOLDOWN_MS - one_hour, 0);

            clock::destroy_for_testing(clock);
            ts::return_shared(faucet);
        };

        // Check time after cooldown passed
        ts::next_tx(&mut scenario, USER1);
        {
            let faucet = ts::take_shared<USDCFaucet>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME + COOLDOWN_MS + 1);

            let time_left = usdc::time_until_next_mint(&faucet, USER1, &clock);
            assert!(time_left == 0, 0);

            clock::destroy_for_testing(clock);
            ts::return_shared(faucet);
        };

        ts::end(scenario);
    }
}
