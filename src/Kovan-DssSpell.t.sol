pragma solidity 0.6.12;

import "ds-math/math.sol";
import "ds-test/test.sol";
import "lib/dss-interfaces/src/Interfaces.sol";
import "./test/rates.sol";
import "./test/addresses_kovan.sol";

import {DssSpell} from "./Kovan-DssSpell.sol";

interface Hevm {
    function warp(uint) external;
    function store(address,bytes32,bytes32) external;
    function load(address,bytes32) external view returns (bytes32);
}

interface SpellLike {
    function done() external view returns (bool);
    function cast() external;
}

contract DssSpellTest is DSTest, DSMath {

    struct SpellValues {
        address deployed_spell;
        uint256 deployed_spell_created;
        address previous_spell;
        uint256 previous_spell_execution_time;
        bool    office_hours_enabled;
        uint256 expiration_threshold;
    }

    struct CollateralValues {
        bool aL_enabled;
        uint256 aL_line;
        uint256 aL_gap;
        uint256 aL_ttl;
        uint256 line;
        uint256 dust;
        uint256 pct;
        uint256 mat;
        bytes32 liqType;
        bool    liqOn;
        uint256 chop;
        uint256 cat_dunk;
        uint256 flip_beg;
        uint48  flip_ttl;
        uint48  flip_tau;
        uint256 flipper_mom;
        uint256 dog_hole;
        uint256 clip_buf;
        uint256 clip_tail;
        uint256 clip_cusp;
        uint256 clip_chip;
        uint256 clip_tip;
        uint256 clipper_mom;
        uint256 calc_tau;
        uint256 calc_step;
        uint256 calc_cut;
    }

    struct SystemValues {
        uint256 pot_dsr;
        uint256 pause_delay;
        uint256 vow_wait;
        uint256 vow_dump;
        uint256 vow_sump;
        uint256 vow_bump;
        uint256 vow_hump_min;
        uint256 vow_hump_max;
        uint256 flap_beg;
        uint256 flap_ttl;
        uint256 flap_tau;
        uint256 cat_box;
        uint256 dog_Hole;
        address pause_authority;
        address osm_mom_authority;
        address flipper_mom_authority;
        address clipper_mom_authority;
        uint256 ilk_count;
        mapping (bytes32 => CollateralValues) collaterals;
    }

    SystemValues afterSpell;
    SpellValues  spellValues;

    Hevm hevm;
    Rates     rates = new Rates();
    Addresses addr  = new Addresses();

    // KOVAN ADDRESSES
    DSPauseAbstract        pause = DSPauseAbstract(    addr.addr("MCD_PAUSE"));
    address           pauseProxy =                     addr.addr("MCD_PAUSE_PROXY");
    DSChiefAbstract        chief = DSChiefAbstract(    addr.addr("MCD_ADM"));
    VatAbstract              vat = VatAbstract(        addr.addr("MCD_VAT"));
    VowAbstract              vow = VowAbstract(        addr.addr("MCD_VOW"));
    CatAbstract              cat = CatAbstract(        addr.addr("MCD_CAT"));
    DogAbstract              dog = DogAbstract(        addr.addr("MCD_DOG"));
    PotAbstract              pot = PotAbstract(        addr.addr("MCD_POT"));
    JugAbstract              jug = JugAbstract(        addr.addr("MCD_JUG"));
    SpotAbstract         spotter = SpotAbstract(       addr.addr("MCD_SPOT"));
    DaiAbstract              dai = DaiAbstract(        addr.addr("MCD_DAI"));
    DaiJoinAbstract      daiJoin = DaiJoinAbstract(    addr.addr("MCD_JOIN_DAI"));
    DSTokenAbstract          gov = DSTokenAbstract(    addr.addr("MCD_GOV"));
    EndAbstract              end = EndAbstract(        addr.addr("MCD_END"));
    ESMAbstract              esm = ESMAbstract(        addr.addr("MCD_ESM"));
    IlkRegistryAbstract      reg = IlkRegistryAbstract(addr.addr("ILK_REGISTRY"));
    FlapAbstract            flap = FlapAbstract(       addr.addr("MCD_FLAP"));

    OsmMomAbstract        osmMom = OsmMomAbstract(     addr.addr("OSM_MOM"));
    FlipperMomAbstract   flipMom = FlipperMomAbstract( addr.addr("FLIPPER_MOM"));
    ClipperMomAbstract   clipMom = ClipperMomAbstract( addr.addr("CLIPPER_MOM"));
    DssAutoLineAbstract autoLine = DssAutoLineAbstract(addr.addr("MCD_IAM_AUTO_LINE"));

    // Faucet
    FaucetAbstract        faucet = FaucetAbstract(     addr.addr("FAUCET"));

    DssSpell spell;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE =
        bytes20(uint160(uint256(keccak256('hevm cheat code'))));

    uint256 constant HUNDRED    = 10 ** 2;
    uint256 constant THOUSAND   = 10 ** 3;
    uint256 constant MILLION    = 10 ** 6;
    uint256 constant BILLION    = 10 ** 9;
    uint256 constant RAD        = 10 ** 45;

    uint256 constant monthly_expiration = 4 days;
    uint256 constant weekly_expiration = 30 days;

    event Debug(uint256 index, uint256 val);
    event Debug(uint256 index, address addr);
    event Debug(uint256 index, bytes32 what);
    event Log(string message, address deployer, string contractName);

    // Many of the settings that change weekly rely on the rate accumulator
    // described at https://docs.makerdao.com/smart-contract-modules/rates-module
    // To check this yourself, use the following rate calculation (example 8%):
    //
    // $ bc -l <<< 'scale=27; e( l(1.01)/(60 * 60 * 24 * 365) )'
    //
    // Rates table is in ./test/rates.sol

    // not provided in DSMath
    function rpow(uint256 x, uint256 n, uint256 b) internal pure returns (uint256 z) {
      assembly {
        switch x case 0 {switch n case 0 {z := b} default {z := 0}}
        default {
          switch mod(n, 2) case 0 { z := b } default { z := x }
          let half := div(b, 2)  // for rounding.
          for { n := div(n, 2) } n { n := div(n,2) } {
            let xx := mul(x, x)
            if iszero(eq(div(xx, x), x)) { revert(0,0) }
            let xxRound := add(xx, half)
            if lt(xxRound, xx) { revert(0,0) }
            x := div(xxRound, b)
            if mod(n,2) {
              let zx := mul(z, x)
              if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
              let zxRound := add(zx, half)
              if lt(zxRound, zx) { revert(0,0) }
              z := div(zxRound, b)
            }
          }
        }
      }
    }
    function divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(x, sub(y, 1)) / y;
    }
    // 10^-5 (tenth of a basis point) as a RAY
    uint256 TOLERANCE = 10 ** 22;

    function yearlyYield(uint256 duty) public pure returns (uint256) {
        return rpow(duty, (365 * 24 * 60 *60), RAY);
    }

    function expectedRate(uint256 percentValue) public pure returns (uint256) {
        return (10000 + percentValue) * (10 ** 23);
    }

    function diffCalc(uint256 expectedRate_, uint256 yearlyYield_) public pure returns (uint256) {
        return (expectedRate_ > yearlyYield_) ? expectedRate_ - yearlyYield_ : yearlyYield_ - expectedRate_;
    }

    function castPreviousSpell() internal {
        SpellLike prevSpell = SpellLike(spellValues.previous_spell);
        // warp and cast previous spell so values are up-to-date to test against
        if (prevSpell != SpellLike(0) && !prevSpell.done()) {
            hevm.warp(spellValues.previous_spell_execution_time);
            prevSpell.cast();
        }
    }

    function setUp() public {
        hevm = Hevm(address(CHEAT_CODE));

        //
        // Test for spell-specific parameters
        //
        spellValues = SpellValues({
            deployed_spell:                 address(0),        // populate with deployed spell if deployed
            deployed_spell_created:         1619559872,                 // use get-created-timestamp.sh if deployed
            previous_spell:                 address(0),        // supply if there is a need to test prior to its cast() function being called on-chain.
            previous_spell_execution_time:  1614790361,                 // Time to warp to in order to allow the previous spell to be cast ignored if PREV_SPELL is SpellLike(address(0)).
            office_hours_enabled:           false,              // true if officehours is expected to be enabled in the spell
            expiration_threshold:           weekly_expiration  // (weekly_expiration,monthly_expiration) if weekly or monthly spell
        });
        spell = spellValues.deployed_spell != address(0) ?
            DssSpell(spellValues.deployed_spell) : new DssSpell();

        //
        // Test for all system configuration changes
        //
        afterSpell = SystemValues({
            pot_dsr:               0,                   // In basis points
            pause_delay:           60,                  // In seconds
            vow_wait:              3600,                // In seconds
            vow_dump:              2,                   // In whole Dai units
            vow_sump:              50,                  // In whole Dai units
            vow_bump:              10,                  // In whole Dai units
            vow_hump_min:          500,                 // In whole Dai units
            vow_hump_max:          1000,                // In whole Dai units
            flap_beg:              200,                 // In Basis Points
            flap_ttl:              1 hours,             // In seconds
            flap_tau:              1 hours,             // In seconds
            cat_box:               10 * THOUSAND,       // In whole Dai units
            dog_Hole:              10 * THOUSAND,       // In whole Dai units
            pause_authority:       address(chief),      // Pause authority
            osm_mom_authority:     address(chief),      // OsmMom authority
            flipper_mom_authority: address(chief),      // FlipperMom authority
            clipper_mom_authority: address(chief),      // ClipperMom authority
            ilk_count:             27                   // Num expected in system
        });

        //
        // Test for all collateral based changes here
        //
        afterSpell.collaterals["ETH-A"] = CollateralValues({
            aL_enabled:   false,           // DssAutoLine is enabled?
            aL_line:      0 * MILLION,     // In whole Dai units
            aL_gap:       0 * MILLION,     // In whole Dai units
            aL_ttl:       0,               // In seconds
            line:         540 * MILLION,   // In whole Dai units
            dust:         100,             // In whole Dai units
            pct:          400,             // In basis points
            mat:          15000,           // In basis points
            liqType:      "clip",          // "" or "flip" or "clip"
            liqOn:        true,            // If liquidations are enabled
            chop:         1300,            // In basis points
            cat_dunk:     0,               // In whole Dai units
            flip_beg:     0,               // In basis points
            flip_ttl:     0,               // In seconds
            flip_tau:     0,               // In seconds
            flipper_mom:  0,               // 1 if circuit breaker enabled
            dog_hole:     5 * THOUSAND,
            clip_buf:     13000,
            clip_tail:    140 minutes,
            clip_cusp:    4000,
            clip_chip:    10,
            clip_tip:     0,
            clipper_mom:  1,
            calc_tau:     0,
            calc_step:    90,
            calc_cut:     9900
        });
        afterSpell.collaterals["ETH-B"] = CollateralValues({
            aL_enabled:   true,
            aL_line:      50 * MILLION,
            aL_gap:       5 * MILLION,
            aL_ttl:       12 hours,
            line:         0 * MILLION,     // Not being checked as there is auto line
            dust:         100,
            pct:          600,
            mat:          13000,
            liqType:      "clip",
            liqOn:        true,
            chop:         1300,
            cat_dunk:     0,
            flip_beg:     0,
            flip_ttl:     0,
            flip_tau:     0,
            flipper_mom:  0,
            dog_hole:     5 * THOUSAND,
            clip_buf:     13000,
            clip_tail:    140 minutes,
            clip_cusp:    4000,
            clip_chip:    10,
            clip_tip:     0,
            clipper_mom:  1,
            calc_tau:     0,
            calc_step:    90,
            calc_cut:     9900
        });
        afterSpell.collaterals["ETH-C"] = CollateralValues({
            aL_enabled:   true,
            aL_line:      2000 * MILLION,
            aL_gap:       100 * MILLION,
            aL_ttl:       12 hours,
            line:         0 * MILLION,
            dust:         100,
            pct:          350,
            mat:          17500,
            liqType:      "clip",
            liqOn:        true,
            chop:         1300,
            cat_dunk:     0,
            flip_beg:     0,
            flip_ttl:     0,
            flip_tau:     0,
            flipper_mom:  0,
            dog_hole:     5 * THOUSAND,
            clip_buf:     13000,
            clip_tail:    140 minutes,
            clip_cusp:    4000,
            clip_chip:    10,
            clip_tip:     0,
            clipper_mom:  1,
            calc_tau:     0,
            calc_step:    90,
            calc_cut:     9900
        });
        afterSpell.collaterals["BAT-A"] = CollateralValues({
            aL_enabled:   false,
            aL_line:      0 * MILLION,
            aL_gap:       0 * MILLION,
            aL_ttl:       0,
            line:         5 * MILLION,
            dust:         100,
            pct:          400,
            mat:          15000,
            liqType:      "clip",
            liqOn:        true,
            chop:         1300,
            cat_dunk:     0,
            flip_beg:     0,
            flip_ttl:     0,
            flip_tau:     0,
            flipper_mom:  0,
            dog_hole:     5 * THOUSAND,
            clip_buf:     13000,
            clip_tail:    140 minutes,
            clip_cusp:    4000,
            clip_chip:    10,
            clip_tip:     0,
            clipper_mom:  1,
            calc_tau:     0,
            calc_step:    90,
            calc_cut:     9900
        });
        afterSpell.collaterals["USDC-A"] = CollateralValues({
            aL_enabled:   false,
            aL_line:      0 * MILLION,
            aL_gap:       0 * MILLION,
            aL_ttl:       0,
            line:         400 * MILLION,
            dust:         100,
            pct:          400,
            mat:          10100,
            liqType:      "flip",
            liqOn:        false,
            chop:         1300,
            cat_dunk:     500,
            flip_beg:     300,
            flip_ttl:     1 hours,
            flip_tau:     1 hours,
            flipper_mom:  1,
            dog_hole:     0,
            clip_buf:     0,
            clip_tail:    0,
            clip_cusp:    0,
            clip_chip:    0,
            clip_tip:     0,
            clipper_mom:  0,
            calc_tau:     0,
            calc_step:    0,
            calc_cut:     0
        });
        afterSpell.collaterals["USDC-B"] = CollateralValues({
            aL_enabled:   false,
            aL_line:      0 * MILLION,
            aL_gap:       0 * MILLION,
            aL_ttl:       0,
            line:         30 * MILLION,
            dust:         100,
            pct:          5000,
            mat:          12000,
            liqType:      "flip",
            liqOn:        false,
            chop:         1300,
            cat_dunk:     500,
            flip_beg:     300,
            flip_ttl:     1 hours,
            flip_tau:     1 hours,
            flipper_mom:  1,
            dog_hole:     0,
            clip_buf:     0,
            clip_tail:    0,
            clip_cusp:    0,
            clip_chip:    0,
            clip_tip:     0,
            clipper_mom:  0,
            calc_tau:     0,
            calc_step:    0,
            calc_cut:     0
        });
        afterSpell.collaterals["WBTC-A"] = CollateralValues({
            aL_enabled:   false,
            aL_line:      0 * MILLION,
            aL_gap:       0 * MILLION,
            aL_ttl:       0,
            line:         120 * MILLION,
            dust:         100,
            pct:          400,
            mat:          15000,
            liqType:      "clip",
            liqOn:        true,
            chop:         1300,
            cat_dunk:     0,
            flip_beg:     0,
            flip_ttl:     0,
            flip_tau:     0,
            flipper_mom:  0,
            dog_hole:     5 * THOUSAND,
            clip_buf:     13000,
            clip_tail:    140 minutes,
            clip_cusp:    4000,
            clip_chip:    10,
            clip_tip:     0,
            clipper_mom:  1,
            calc_tau:     0,
            calc_step:    90,
            calc_cut:     9900
        });
        afterSpell.collaterals["TUSD-A"] = CollateralValues({
            aL_enabled:   false,
            aL_line:      0 * MILLION,
            aL_gap:       0 * MILLION,
            aL_ttl:       0,
            line:         50 * MILLION,
            dust:         100,
            pct:          400,
            mat:          10100,
            liqType:      "flip",
            liqOn:        false,
            chop:         1300,
            cat_dunk:     500,
            flip_beg:     300,
            flip_ttl:     1 hours,
            flip_tau:     1 hours,
            flipper_mom:  1,
            dog_hole:     0,
            clip_buf:     0,
            clip_tail:    0,
            clip_cusp:    0,
            clip_chip:    0,
            clip_tip:     0,
            clipper_mom:  0,
            calc_tau:     0,
            calc_step:    0,
            calc_cut:     0
        });
        afterSpell.collaterals["KNC-A"] = CollateralValues({
            aL_enabled:   false,
            aL_line:      0 * MILLION,
            aL_gap:       0 * MILLION,
            aL_ttl:       0,
            line:         5 * MILLION,
            dust:         100,
            pct:          400,
            mat:          17500,
            liqType:      "clip",
            liqOn:        true,
            chop:         1300,
            cat_dunk:     0,
            flip_beg:     0,
            flip_ttl:     0,
            flip_tau:     0,
            flipper_mom:  0,
            dog_hole:     5 * THOUSAND,
            clip_buf:     13000,
            clip_tail:    140 minutes,
            clip_cusp:    4000,
            clip_chip:    10,
            clip_tip:     0,
            clipper_mom:  1,
            calc_tau:     0,
            calc_step:    90,
            calc_cut:     9900
        });
        afterSpell.collaterals["ZRX-A"] = CollateralValues({
            aL_enabled:   false,
            aL_line:      0 * MILLION,
            aL_gap:       0 * MILLION,
            aL_ttl:       0,
            line:         5 * MILLION,
            dust:         100,
            pct:          400,
            mat:          17500,
            liqType:      "clip",
            liqOn:        true,
            chop:         1300,
            cat_dunk:     0,
            flip_beg:     0,
            flip_ttl:     0,
            flip_tau:     0,
            flipper_mom:  0,
            dog_hole:     5 * THOUSAND,
            clip_buf:     13000,
            clip_tail:    140 minutes,
            clip_cusp:    4000,
            clip_chip:    10,
            clip_tip:     0,
            clipper_mom:  1,
            calc_tau:     0,
            calc_step:    90,
            calc_cut:     9900
        });
        afterSpell.collaterals["MANA-A"] = CollateralValues({
            aL_enabled:   false,
            aL_line:      0 * MILLION,
            aL_gap:       0 * MILLION,
            aL_ttl:       0,
            line:         1 * MILLION,
            dust:         100,
            pct:          1200,
            mat:          17500,
            liqType:      "clip",
            liqOn:        true,
            chop:         1300,
            cat_dunk:     0,
            flip_beg:     0,
            flip_ttl:     0,
            flip_tau:     0,
            flipper_mom:  0,
            dog_hole:     5 * THOUSAND,
            clip_buf:     13000,
            clip_tail:    140 minutes,
            clip_cusp:    4000,
            clip_chip:    10,
            clip_tip:     0,
            clipper_mom:  1,
            calc_tau:     0,
            calc_step:    90,
            calc_cut:     9900
        });
        afterSpell.collaterals["USDT-A"] = CollateralValues({
            aL_enabled:   false,
            aL_line:      0 * MILLION,
            aL_gap:       0 * MILLION,
            aL_ttl:       0,
            line:         10 * MILLION,
            dust:         100,
            pct:          800,
            mat:          15000,
            liqType:      "clip",
            liqOn:        true,
            chop:         1300,
            cat_dunk:     0,
            flip_beg:     0,
            flip_ttl:     0,
            flip_tau:     0,
            flipper_mom:  0,
            dog_hole:     5 * THOUSAND,
            clip_buf:     13000,
            clip_tail:    140 minutes,
            clip_cusp:    4000,
            clip_chip:    10,
            clip_tip:     0,
            clipper_mom:  1,
            calc_tau:     0,
            calc_step:    90,
            calc_cut:     9900
        });
        afterSpell.collaterals["PAXUSD-A"] = CollateralValues({
            aL_enabled:   false,
            aL_line:      0 * MILLION,
            aL_gap:       0 * MILLION,
            aL_ttl:       0,
            line:         30 * MILLION,
            dust:         100,
            pct:          400,
            mat:          10100,
            liqType:      "flip",
            liqOn:        false,
            chop:         1300,
            cat_dunk:     500,
            flip_beg:     300,
            flip_ttl:     1 hours,
            flip_tau:     1 hours,
            flipper_mom:  1,
            dog_hole:     0,
            clip_buf:     0,
            clip_tail:    0,
            clip_cusp:    0,
            clip_chip:    0,
            clip_tip:     0,
            clipper_mom:  0,
            calc_tau:     0,
            calc_step:    0,
            calc_cut:     0
        });
        afterSpell.collaterals["COMP-A"] = CollateralValues({
            aL_enabled:   false,
            aL_line:      0 * MILLION,
            aL_gap:       0 * MILLION,
            aL_ttl:       0,
            line:         7 * MILLION,
            dust:         100,
            pct:          100,
            mat:          17500,
            liqType:      "clip",
            liqOn:        true,
            chop:         1300,
            cat_dunk:     0,
            flip_beg:     0,
            flip_ttl:     0,
            flip_tau:     0,
            flipper_mom:  0,
            dog_hole:     5 * THOUSAND,
            clip_buf:     13000,
            clip_tail:    140 minutes,
            clip_cusp:    4000,
            clip_chip:    10,
            clip_tip:     0,
            clipper_mom:  1,
            calc_tau:     0,
            calc_step:    90,
            calc_cut:     9900
        });
        afterSpell.collaterals["LRC-A"] = CollateralValues({
            aL_enabled:   false,
            aL_line:      0 * MILLION,
            aL_gap:       0 * MILLION,
            aL_ttl:       0,
            line:         3 * MILLION,
            dust:         100,
            pct:          300,
            mat:          17500,
            liqType:      "clip",
            liqOn:        true,
            chop:         1300,
            cat_dunk:     0,
            flip_beg:     0,
            flip_ttl:     0,
            flip_tau:     0,
            flipper_mom:  0,
            dog_hole:     5 * THOUSAND,
            clip_buf:     13000,
            clip_tail:    140 minutes,
            clip_cusp:    4000,
            clip_chip:    10,
            clip_tip:     0,
            clipper_mom:  1,
            calc_tau:     0,
            calc_step:    90,
            calc_cut:     9900
        });
        afterSpell.collaterals["LINK-A"] = CollateralValues({
            aL_enabled:   false,
            aL_line:      0 * MILLION,
            aL_gap:       0 * MILLION,
            aL_ttl:       0,
            line:         5 * MILLION,
            dust:         100,
            pct:          200,
            mat:          17500,
            liqType:      "clip",
            liqOn:        true,
            chop:         1300,
            cat_dunk:     0,
            flip_beg:     0,
            flip_ttl:     0,
            flip_tau:     0,
            flipper_mom:  0,
            dog_hole:     5 * THOUSAND,
            clip_buf:     13000,
            clip_tail:    140 minutes,
            clip_cusp:    4000,
            clip_chip:    10,
            clip_tip:     0,
            clipper_mom:  1,
            calc_tau:     0,
            calc_step:    90,
            calc_cut:     9900
        });
        afterSpell.collaterals["BAL-A"] = CollateralValues({
            aL_enabled:   false,
            aL_line:      0 * MILLION,
            aL_gap:       0 * MILLION,
            aL_ttl:       0,
            line:         4 * MILLION,
            dust:         100,
            pct:          500,
            mat:          17500,
            liqType:      "clip",
            liqOn:        true,
            chop:         1300,
            cat_dunk:     0,
            flip_beg:     0,
            flip_ttl:     0,
            flip_tau:     0,
            flipper_mom:  0,
            dog_hole:     5 * THOUSAND,
            clip_buf:     13000,
            clip_tail:    140 minutes,
            clip_cusp:    4000,
            clip_chip:    10,
            clip_tip:     0,
            clipper_mom:  1,
            calc_tau:     0,
            calc_step:    90,
            calc_cut:     9900
        });
        afterSpell.collaterals["YFI-A"] = CollateralValues({
            aL_enabled:   false,
            aL_line:      0 * MILLION,
            aL_gap:       0 * MILLION,
            aL_ttl:       0,
            line:         7 * MILLION,
            dust:         100,
            pct:          400,
            mat:          17500,
            liqType:      "clip",
            liqOn:        true,
            chop:         1300,
            cat_dunk:     0,
            flip_beg:     0,
            flip_ttl:     0,
            flip_tau:     0,
            flipper_mom:  0,
            dog_hole:     5 * THOUSAND,
            clip_buf:     13000,
            clip_tail:    140 minutes,
            clip_cusp:    4000,
            clip_chip:    10,
            clip_tip:     0,
            clipper_mom:  1,
            calc_tau:     0,
            calc_step:    90,
            calc_cut:     9900
        });
        afterSpell.collaterals["GUSD-A"] = CollateralValues({
            aL_enabled:   false,
            aL_line:      0 * MILLION,
            aL_gap:       0 * MILLION,
            aL_ttl:       0,
            line:         5 * MILLION,
            dust:         100,
            pct:          400,
            mat:          10100,
            liqType:      "flip",
            liqOn:        false,
            chop:         1300,
            cat_dunk:     500,
            flip_beg:     300,
            flip_ttl:     1 hours,
            flip_tau:     1 hours,
            flipper_mom:  1,
            dog_hole:     0,
            clip_buf:     0,
            clip_tail:    0,
            clip_cusp:    0,
            clip_chip:    0,
            clip_tip:     0,
            clipper_mom:  0,
            calc_tau:     0,
            calc_step:    0,
            calc_cut:     0
        });
        afterSpell.collaterals["UNI-A"] = CollateralValues({
            aL_enabled:   false,
            aL_line:      0 * MILLION,
            aL_gap:       0 * MILLION,
            aL_ttl:       0,
            line:         15 * MILLION,
            dust:         100,
            pct:          300,
            mat:          17500,
            liqType:      "clip",
            liqOn:        true,
            chop:         1300,
            cat_dunk:     0,
            flip_beg:     0,
            flip_ttl:     0,
            flip_tau:     0,
            flipper_mom:  0,
            dog_hole:     5 * THOUSAND,
            clip_buf:     13000,
            clip_tail:    140 minutes,
            clip_cusp:    4000,
            clip_chip:    10,
            clip_tip:     0,
            clipper_mom:  1,
            calc_tau:     0,
            calc_step:    90,
            calc_cut:     9900
        });
        afterSpell.collaterals["RENBTC-A"] = CollateralValues({
            aL_enabled:   false,
            aL_line:      0 * MILLION,
            aL_gap:       0 * MILLION,
            aL_ttl:       0,
            line:         2 * MILLION,
            dust:         100,
            pct:          600,
            mat:          17500,
            liqType:      "clip",
            liqOn:        true,
            chop:         1300,
            cat_dunk:     0,
            flip_beg:     0,
            flip_ttl:     0,
            flip_tau:     0,
            flipper_mom:  0,
            dog_hole:     5 * THOUSAND,
            clip_buf:     13000,
            clip_tail:    140 minutes,
            clip_cusp:    4000,
            clip_chip:    10,
            clip_tip:     0,
            clipper_mom:  1,
            calc_tau:     0,
            calc_step:    90,
            calc_cut:     9900
        });
        afterSpell.collaterals["AAVE-A"] = CollateralValues({
            aL_enabled:   false,
            aL_line:      0 * MILLION,
            aL_gap:       0 * MILLION,
            aL_ttl:       0,
            line:         10 * MILLION,
            dust:         100,
            pct:          600,
            mat:          17500,
            liqType:      "clip",
            liqOn:        true,
            chop:         1300,
            cat_dunk:     0,
            flip_beg:     0,
            flip_ttl:     0,
            flip_tau:     0,
            flipper_mom:  0,
            dog_hole:     5 * THOUSAND,
            clip_buf:     13000,
            clip_tail:    140 minutes,
            clip_cusp:    4000,
            clip_chip:    10,
            clip_tip:     0,
            clipper_mom:  1,
            calc_tau:     0,
            calc_step:    90,
            calc_cut:     9900
        });
        afterSpell.collaterals["UNIV2DAIETH-A"] = CollateralValues({
            aL_enabled:   false,
            aL_line:      0 * MILLION,
            aL_gap:       0 * MILLION,
            aL_ttl:       0,
            line:         3 * MILLION,
            dust:         100,
            pct:          100,
            mat:          12500,
            liqType:      "flip",
            liqOn:        true,
            chop:         1300,
            cat_dunk:     500,
            flip_beg:     300,
            flip_ttl:     1 hours,
            flip_tau:     1 hours,
            flipper_mom:  1,
            dog_hole:     0,
            clip_buf:     0,
            clip_tail:    0,
            clip_cusp:    0,
            clip_chip:    0,
            clip_tip:     0,
            clipper_mom:  0,
            calc_tau:     0,
            calc_step:    0,
            calc_cut:     0
        });
        afterSpell.collaterals["PSM-USDC-A"] = CollateralValues({
            aL_enabled:   false,
            aL_line:      0 * MILLION,
            aL_gap:       0 * MILLION,
            aL_ttl:       0,
            line:         500 * MILLION,
            dust:         0,
            pct:          0,
            mat:          10000,
            liqType:      "flip",
            liqOn:        false,
            chop:         1300,
            cat_dunk:     500,
            flip_beg:     300,
            flip_ttl:     1 hours,
            flip_tau:     1 hours,
            flipper_mom:  1,
            dog_hole:     0,
            clip_buf:     0,
            clip_tail:    0,
            clip_cusp:    0,
            clip_chip:    0,
            clip_tip:     0,
            clipper_mom:  0,
            calc_tau:     0,
            calc_step:    0,
            calc_cut:     0
        });
        afterSpell.collaterals["RWA001-A"] = CollateralValues({
            aL_enabled:   false,
            aL_line:      0 * MILLION,
            aL_gap:       0 * MILLION,
            aL_ttl:       0,
            line:         1 * THOUSAND,
            dust:         0,
            pct:          300,
            mat:          10000,
            liqType:      "",
            liqOn:        false,
            chop:         0,
            cat_dunk:     0,
            flip_beg:     0,
            flip_ttl:     0,
            flip_tau:     0,
            flipper_mom:  0,
            dog_hole:     0,
            clip_buf:     0,
            clip_tail:    0,
            clip_cusp:    0,
            clip_chip:    0,
            clip_tip:     0,
            clipper_mom:  0,
            calc_tau:     0,
            calc_step:    0,
            calc_cut:     0
        });
        afterSpell.collaterals["RWA002-A"] = CollateralValues({
            aL_enabled:   false,
            aL_line:      0 * MILLION,
            aL_gap:       0 * MILLION,
            aL_ttl:       0,
            line:         5 * MILLION,
            dust:         0,
            pct:          350,
            mat:          10500,
            liqType:      "",
            liqOn:        false,
            chop:         0,
            cat_dunk:     0,
            flip_beg:     0,
            flip_ttl:     0,
            flip_tau:     0,
            flipper_mom:  0,
            dog_hole:     0,
            clip_buf:     0,
            clip_tail:    0,
            clip_cusp:    0,
            clip_chip:    0,
            clip_tip:     0,
            clipper_mom:  0,
            calc_tau:     0,
            calc_step:    0,
            calc_cut:     0
        });
        afterSpell.collaterals["PAXG-A"] = CollateralValues({
            aL_enabled:   false,
            aL_line:      0 * MILLION,
            aL_gap:       0 * MILLION,
            aL_ttl:       0,
            line:         5 * MILLION,
            dust:         100,
            pct:          400,
            mat:          12500,
            liqType:      "flip",
            liqOn:        true,
            chop:         1300,
            cat_dunk:     500,
            flip_beg:     300,
            flip_ttl:     1 hours,
            flip_tau:     1 hours,
            flipper_mom:  1,
            dog_hole:     0,
            clip_buf:     0,
            clip_tail:    0,
            clip_cusp:    0,
            clip_chip:    0,
            clip_tip:     0,
            clipper_mom:  0,
            calc_tau:     0,
            calc_step:    0,
            calc_cut:     0
        });
    }

    function scheduleWaitAndCastFailDay() public {
        spell.schedule();

        uint256 castTime = block.timestamp + pause.delay();
        uint256 day = (castTime / 1 days + 3) % 7;
        if (day < 5) {
            castTime += 5 days - day * 86400;
        }

        hevm.warp(castTime);
        spell.cast();
    }

    function scheduleWaitAndCastFailEarly() public {
        spell.schedule();

        uint256 castTime = block.timestamp + pause.delay() + 24 hours;
        uint256 hour = castTime / 1 hours % 24;
        if (hour >= 14) {
            castTime -= hour * 3600 - 13 hours;
        }

        hevm.warp(castTime);
        spell.cast();
    }

    function scheduleWaitAndCastFailLate() public {
        spell.schedule();

        uint256 castTime = block.timestamp + pause.delay();
        uint256 hour = castTime / 1 hours % 24;
        if (hour < 21) {
            castTime += 21 hours - hour * 3600;
        }

        hevm.warp(castTime);
        spell.cast();
    }

    function vote(address spell_) private {
        if (chief.hat() != spell_) {
            hevm.store(
                address(gov),
                keccak256(abi.encode(address(this), uint256(1))),
                bytes32(uint256(999999999999 ether))
            );
            gov.approve(address(chief), uint256(-1));
            chief.lock(999999999999 ether);

            address[] memory slate = new address[](1);

            assertTrue(!DssSpell(spell_).done());

            slate[0] = spell_;

            chief.vote(slate);
            chief.lift(spell_);
        }
        assertEq(chief.hat(), spell_);
    }

    function scheduleWaitAndCast(address spell_) public {
        DssSpell(spell_).schedule();

        hevm.warp(DssSpell(spell_).nextCastTime());

        DssSpell(spell_).cast();
    }

    function stringToBytes32(string memory source) public pure returns (bytes32 result) {
        assembly {
            result := mload(add(source, 32))
        }
    }

    function checkSystemValues(SystemValues storage values) internal {
        // dsr
        uint256 expectedDSRRate = rates.rates(values.pot_dsr);
        // make sure dsr is less than 100% APR
        // bc -l <<< 'scale=27; e( l(2.00)/(60 * 60 * 24 * 365) )'
        // 1000000021979553151239153027
        assertTrue(
            pot.dsr() >= RAY && pot.dsr() < 1000000021979553151239153027
        );
        assertTrue(diffCalc(expectedRate(values.pot_dsr), yearlyYield(expectedDSRRate)) <= TOLERANCE);

        {
        // Line values in RAD
        assertTrue(
            (vat.Line() >= RAD && vat.Line() < 100 * BILLION * RAD) ||
            vat.Line() == 0
        );
        }

        // Pause delay
        assertEq(pause.delay(), values.pause_delay);

        // wait
        assertEq(vow.wait(), values.vow_wait);
        {
        // dump values in WAD
        uint256 normalizedDump = values.vow_dump * WAD;
        assertEq(vow.dump(), normalizedDump);
        assertTrue(
            (vow.dump() >= WAD && vow.dump() < 2 * THOUSAND * WAD) ||
            vow.dump() == 0
        );
        }
        {
        // sump values in RAD
        uint256 normalizedSump = values.vow_sump * RAD;
        assertEq(vow.sump(), normalizedSump);
        assertTrue(
            (vow.sump() >= RAD && vow.sump() < 500 * THOUSAND * RAD) ||
            vow.sump() == 0
        );
        }
        {
        // bump values in RAD
        uint256 normalizedBump = values.vow_bump * RAD;
        assertEq(vow.bump(), normalizedBump);
        assertTrue(
            (vow.bump() >= RAD && vow.bump() < HUNDRED * THOUSAND * RAD) ||
            vow.bump() == 0
        );
        }
        {
        // hump values in RAD
        uint256 normalizedHumpMin = values.vow_hump_min * RAD;
        uint256 normalizedHumpMax = values.vow_hump_max * RAD;
        assertTrue(vow.hump() >= normalizedHumpMin && vow.hump() <= normalizedHumpMax);
        assertTrue(
            (vow.hump() >= RAD && vow.hump() < HUNDRED * MILLION * RAD) ||
            vow.hump() == 0
        );
        }

        // box value in RAD
        {
            uint256 normalizedBox = values.cat_box * RAD;
            assertEq(cat.box(), normalizedBox);
            assertTrue(cat.box() >= THOUSAND * RAD);
            assertTrue(cat.box() < 50 * MILLION * RAD);
        }

        // Hole value in RAD
        {
            uint256 normalizedHole = values.dog_Hole * RAD;
            assertEq(dog.Hole(), normalizedHole);
            assertTrue(dog.Hole() >= THOUSAND * RAD);
            assertTrue(dog.Hole() < 50 * MILLION * RAD);
        }

        // check Pause authority
        assertEq(pause.authority(), values.pause_authority);

        // check OsmMom authority
        assertEq(osmMom.authority(), values.osm_mom_authority);

        // check FlipperMom authority
        assertEq(flipMom.authority(), values.flipper_mom_authority);

        // check ClipperMom authority
        assertEq(clipMom.authority(), values.clipper_mom_authority);

        // check number of ilks
        assertEq(reg.count(), values.ilk_count);

        // flap
        // check beg value
        uint256 normalizedTestBeg = (values.flap_beg + 10000)  * 10**14;
        assertEq(flap.beg(), normalizedTestBeg);
        assertTrue(flap.beg() >= WAD && flap.beg() <= 110 * WAD / 100); // gte 0% and lte 10%
        // Check flap ttl and sanity checks
        assertEq(flap.ttl(), values.flap_ttl);
        assertTrue(flap.ttl() > 0 && flap.ttl() < 86400); // gt 0 && lt 1 day
        // Check flap tau and sanity checks
        assertEq(flap.tau(), values.flap_tau);
        assertTrue(flap.tau() > 0 && flap.tau() < 2678400); // gt 0 && lt 1 month
        assertTrue(flap.tau() >= flap.ttl());
    }

    function checkCollateralValues(SystemValues storage values) internal {
        uint256 sumlines;
        bytes32[] memory ilks = reg.list();
        for(uint256 i = 0; i < ilks.length; i++) {
            bytes32 ilk = ilks[i];
            (uint256 duty,)  = jug.ilks(ilk);

            assertEq(duty, rates.rates(values.collaterals[ilk].pct));
            // make sure duty is less than 1000% APR
            // bc -l <<< 'scale=27; e( l(10.00)/(60 * 60 * 24 * 365) )'
            // 1000000073014496989316680335
            assertTrue(duty >= RAY && duty < 1000000073014496989316680335);  // gt 0 and lt 1000%
            assertTrue(diffCalc(expectedRate(values.collaterals[ilk].pct), yearlyYield(rates.rates(values.collaterals[ilk].pct))) <= TOLERANCE);
            assertTrue(values.collaterals[ilk].pct < THOUSAND * THOUSAND);   // check value lt 1000%
            {
            (,,, uint256 line, uint256 dust) = vat.ilks(ilk);
            // Convert whole Dai units to expected RAD
            uint256 normalizedTestLine = values.collaterals[ilk].line * RAD;
            sumlines += line;
            (uint256 aL_line, uint256 aL_gap, uint256 aL_ttl,,) = autoLine.ilks(ilk);
            if (!values.collaterals[ilk].aL_enabled) {
                assertTrue(aL_line == 0);
                assertEq(line, normalizedTestLine);
                assertTrue((line >= RAD && line < 10 * BILLION * RAD) || line == 0);  // eq 0 or gt eq 1 RAD and lt 10B
            } else {
                assertTrue(aL_line > 0);
                assertEq(aL_line, values.collaterals[ilk].aL_line * RAD);
                assertEq(aL_gap, values.collaterals[ilk].aL_gap * RAD);
                assertEq(aL_ttl, values.collaterals[ilk].aL_ttl);
                assertTrue((aL_line >= RAD && aL_line < 10 * BILLION * RAD) || aL_line == 0); // eq 0 or gt eq 1 RAD and lt 10B
            }
            uint256 normalizedTestDust = values.collaterals[ilk].dust * RAD;
            assertEq(dust, normalizedTestDust);
            assertTrue((dust >= RAD && dust < 10 * THOUSAND * RAD) || dust == 0); // eq 0 or gt eq 1 and lt 10k
            }

            {
            (,uint256 mat) = spotter.ilks(ilk);
            // Convert BP to system expected value
            uint256 normalizedTestMat = (values.collaterals[ilk].mat * 10**23);
            assertEq(mat, normalizedTestMat);
            assertTrue(mat >= RAY && mat < 10 * RAY);    // cr eq 100% and lt 1000%
            }

            if (values.collaterals[ilk].liqType == "flip") {
                {
                assertEq(reg.class(ilk), 2);
                (bool ok, bytes memory val) = reg.xlip(ilk).call(abi.encodeWithSignature("cat()"));
                assertTrue(ok);
                assertEq(abi.decode(val, (address)), address(cat));
                }
                {
                (, uint256 chop, uint256 dunk) = cat.ilks(ilk);
                // Convert BP to system expected value
                uint256 normalizedTestChop = (values.collaterals[ilk].chop * 10**14) + WAD;
                assertEq(chop, normalizedTestChop);
                // make sure chop is less than 100%
                assertTrue(chop >= WAD && chop < 2 * WAD);   // penalty gt eq 0% and lt 100%

                // Convert whole Dai units to expected RAD
                uint256 normalizedTestDunk = values.collaterals[ilk].cat_dunk * RAD;
                assertEq(dunk, normalizedTestDunk);
                assertTrue(dunk >= RAD && dunk < MILLION * RAD);

                (address flipper,,) = cat.ilks(ilk);
                FlipAbstract flip = FlipAbstract(flipper);
                // Convert BP to system expected value
                uint256 normalizedTestBeg = (values.collaterals[ilk].flip_beg + 10000)  * 10**14;
                assertEq(uint256(flip.beg()), normalizedTestBeg);
                assertTrue(flip.beg() >= WAD && flip.beg() <= 110 * WAD / 100); // gte 0% and lte 10%
                assertEq(uint256(flip.ttl()), values.collaterals[ilk].flip_ttl);
                assertTrue(flip.ttl() >= 600 && flip.ttl() < 10 hours);         // gt eq 10 minutes and lt 10 hours
                assertEq(uint256(flip.tau()), values.collaterals[ilk].flip_tau);
                assertTrue(flip.tau() >= 600 && flip.tau() <= 3 days);          // gt eq 10 minutes and lt eq 3 days

                assertEq(flip.wards(address(flipMom)), values.collaterals[ilk].flipper_mom);

                assertEq(flip.wards(address(cat)), values.collaterals[ilk].liqOn ? 1 : 0);
                assertEq(flip.wards(address(pauseProxy)), 1); // Check pause_proxy ward
                }
            }
            if (values.collaterals[ilk].liqType == "clip") {
                {
                assertEq(reg.class(ilk), 1);
                (bool ok, bytes memory val) = reg.xlip(ilk).call(abi.encodeWithSignature("dog()"));
                assertTrue(ok);
                assertEq(abi.decode(val, (address)), address(dog));
                }
                {
                (, uint256 chop, uint256 hole,) = dog.ilks(ilk);
                // Convert BP to system expected value
                uint256 normalizedTestChop = (values.collaterals[ilk].chop * 10**14) + WAD;
                assertEq(chop, normalizedTestChop);
                // make sure chop is less than 100%
                assertTrue(chop >= WAD && chop < 2 * WAD);   // penalty gt eq 0% and lt 100%

                // Convert whole Dai units to expected RAD
                uint256 normalizedTesthole = values.collaterals[ilk].dog_hole * RAD;
                assertEq(hole, normalizedTesthole);
                assertTrue(hole >= RAD && hole < 20 * MILLION * RAD);
                }
                (address clipper,,,) = dog.ilks(ilk);
                ClipAbstract clip = ClipAbstract(clipper);
                {
                // Convert BP to system expected value
                uint256 normalizedTestBuf = values.collaterals[ilk].clip_buf * 10**23;
                assertEq(uint256(clip.buf()), normalizedTestBuf);
                assertTrue(clip.buf() >= RAY && clip.buf() <= 2 * RAY); // gte 0% and lte 100%
                assertEq(uint256(clip.tail()), values.collaterals[ilk].clip_tail);
                assertTrue(clip.tail() >= 1200 && clip.tail() < 10 hours); // gt eq 20 minutes and lt 10 hours
                uint256 normalizedTestCusp = (values.collaterals[ilk].clip_cusp)  * 10**23;
                assertEq(uint256(clip.cusp()), normalizedTestCusp);
                assertTrue(clip.cusp() >= RAY / 10 && clip.cusp() < RAY); // gte 10% and lt 100%
                assertTrue(rmul(clip.buf(), clip.cusp()) <= RAY);
                uint256 normalizedTestChip = (values.collaterals[ilk].clip_chip)  * 10**14;
                assertEq(uint256(clip.chip()), normalizedTestChip);
                assertTrue(clip.chip() < 1 * WAD / 100); // lt 13% (typical liquidation penalty)
                uint256 normalizedTestTip = values.collaterals[ilk].clip_tip * RAD;
                assertEq(uint256(clip.tip()), normalizedTestTip);
                assertTrue(clip.tip() == 0 || clip.tip() >= RAD && clip.tip() <= 100 * RAD);

                assertEq(clip.wards(address(clipMom)), values.collaterals[ilk].clipper_mom);

                if (values.collaterals[ilk].liqOn) {
                    assertEq(clip.stopped(), 0);
                } else {
                    assertTrue(clip.stopped() > 0);
                }

                assertEq(clip.wards(address(pauseProxy)), 1); // Check pause_proxy ward
                }
                {
                    (bool exists, bytes memory value) = clip.calc().call(abi.encodeWithSignature("tau()"));
                    assertEq(exists ? abi.decode(value, (uint256)) : 0, values.collaterals[ilk].calc_tau);
                    (exists, value) = clip.calc().call(abi.encodeWithSignature("step()"));
                    assertEq(exists ? abi.decode(value, (uint256)) : 0, values.collaterals[ilk].calc_step);
                    if (exists) {
                       assertTrue(abi.decode(value, (uint256)) > 0);
                    }
                    (exists, value) = clip.calc().call(abi.encodeWithSignature("cut()"));
                    uint256 normalizedTestCut = values.collaterals[ilk].calc_cut * 10**23;
                    assertEq(exists ? abi.decode(value, (uint256)) : 0, normalizedTestCut);
                    if (exists) {
                       assertTrue(abi.decode(value, (uint256)) > 0 && abi.decode(value, (uint256)) < RAY);
                    }
                }
            }
            if (reg.class(ilk) < 3) {
                {
                GemJoinAbstract join = GemJoinAbstract(reg.join(ilk));
                assertEq(join.wards(address(pauseProxy)), 1); // Check pause_proxy ward
                }
            }
        }
        //       actual    expected
        assertEq(sumlines, vat.Line());
    }

    function getOSMPrice(address pip) internal returns (uint256) {
        // hevm.load is to pull the price from the LP Oracle storage bypassing the whitelist
        uint256 price = uint256(hevm.load(
            pip,
            bytes32(uint256(3))
        )) & uint128(-1);   // Price is in the second half of the 32-byte storage slot

        // Price is bounded in the spot by around 10^23
        // Give a 10^9 buffer for price appreciation over time
        // Note: This currently can't be hit due to the uint112, but we want to backstop
        //       once the PIP uint256 size is increased
        assertTrue(price <= (10 ** 14) * WAD);

        return price;
    }

    function getUNIV2LPPrice(address pip) internal returns (uint256) {
        // hevm.load is to pull the price from the LP Oracle storage bypassing the whitelist
        uint256 price = uint256(hevm.load(
            pip,
            bytes32(uint256(6))
        )) & uint128(-1);   // Price is in the second half of the 32-byte storage slot

        // Price is bounded in the spot by around 10^23
        // Give a 10^9 buffer for price appreciation over time
        // Note: This currently can't be hit due to the uint112, but we want to backstop
        //       once the PIP uint256 size is increased
        assertTrue(price <= (10 ** 14) * WAD);

        return price;
    }

    function giveTokens(DSTokenAbstract token, uint256 amount) internal {
        // Edge case - balance is already set for some reason
        if (token.balanceOf(address(this)) == amount) return;

        for (int i = 0; i < 100; i++) {
            // Scan the storage for the balance storage slot
            bytes32 prevValue = hevm.load(
                address(token),
                keccak256(abi.encode(address(this), uint256(i)))
            );
            hevm.store(
                address(token),
                keccak256(abi.encode(address(this), uint256(i))),
                bytes32(amount)
            );
            if (token.balanceOf(address(this)) == amount) {
                // Found it
                return;
            } else {
                // Keep going after restoring the original value
                hevm.store(
                    address(token),
                    keccak256(abi.encode(address(this), uint256(i))),
                    prevValue
                );
            }
        }

        // We have failed if we reach here
        assertTrue(false);
    }

	function checkIlkIntegration(
        bytes32 _ilk,
        GemJoinAbstract join,
        FlipAbstract flip,
        address pip,
        bool _isOSM,
        bool _checkLiquidations,
        bool _transferFee
    ) public {
        DSTokenAbstract token = DSTokenAbstract(join.gem());

        if (_isOSM) OsmAbstract(pip).poke();
        hevm.warp(block.timestamp + 3601);
        if (_isOSM) OsmAbstract(pip).poke();
        spotter.poke(_ilk);

        // Authorization
        assertEq(join.wards(pauseProxy), 1);
        assertEq(vat.wards(address(join)), 1);
        assertEq(flip.wards(address(end)), 1);
        assertEq(flip.wards(address(flipMom)), 1);
        if (_isOSM) {
            assertEq(OsmAbstract(pip).wards(address(osmMom)), 1);
            assertEq(OsmAbstract(pip).bud(address(spotter)), 1);
            assertEq(OsmAbstract(pip).bud(address(end)), 1);
            assertEq(MedianAbstract(OsmAbstract(pip).src()).bud(pip), 1);
        }

        (,,,, uint256 dust) = vat.ilks(_ilk);
        dust /= RAY;
        uint256 amount = 2 * dust * WAD / (_isOSM ? getOSMPrice(pip) : uint256(DSValueAbstract(pip).read()));
        giveTokens(token, amount);

        assertEq(token.balanceOf(address(this)), amount);
        assertEq(vat.gem(_ilk, address(this)), 0);
        token.approve(address(join), amount);
        join.join(address(this), amount);
        assertEq(token.balanceOf(address(this)), 0);
        if (_transferFee) {
            amount = vat.gem(_ilk, address(this));
            assertTrue(amount > 0);
        }
        assertEq(vat.gem(_ilk, address(this)), amount);

        // Tick the fees forward so that art != dai in wad units
        hevm.warp(block.timestamp + 1);
        jug.drip(_ilk);

        // Deposit collateral, generate DAI
        (,uint256 rate,,,) = vat.ilks(_ilk);
        assertEq(vat.dai(address(this)), 0);
        vat.frob(_ilk, address(this), address(this), address(this), int256(amount), int256(divup(mul(RAY, dust), rate)));
        assertEq(vat.gem(_ilk, address(this)), 0);
        assertTrue(vat.dai(address(this)) >= dust * RAY);
        assertTrue(vat.dai(address(this)) <= (dust + 1) * RAY);

        // Payback DAI, withdraw collateral
        vat.frob(_ilk, address(this), address(this), address(this), -int256(amount), -int256(divup(mul(RAY, dust), rate)));
        assertEq(vat.gem(_ilk, address(this)), amount);
        assertEq(vat.dai(address(this)), 0);

        // Withdraw from adapter
        join.exit(address(this), amount);
        if (_transferFee) {
            amount = token.balanceOf(address(this));
        }
        assertEq(token.balanceOf(address(this)), amount);
        assertEq(vat.gem(_ilk, address(this)), 0);

        // Generate new DAI to force a liquidation
        token.approve(address(join), amount);
        join.join(address(this), amount);
        if (_transferFee) {
            amount = vat.gem(_ilk, address(this));
        }
        // dart max amount of DAI
        (,,uint256 spotV,,) = vat.ilks(_ilk);
        vat.frob(_ilk, address(this), address(this), address(this), int256(amount), int256(mul(amount, spotV) / rate));
        hevm.warp(block.timestamp + 1);
        jug.drip(_ilk);
        assertEq(flip.kicks(), 0);
        if (_checkLiquidations) {
            cat.bite(_ilk, address(this));
            assertEq(flip.kicks(), 1);
        }

        // Dump all dai for next run
        vat.move(address(this), address(0x0), vat.dai(address(this)));
    }

	function checkUNIV2LPIntegration(
        bytes32 _ilk,
        GemJoinAbstract join,
        FlipAbstract flip,
        LPOsmAbstract pip,
        address _medianizer1,
        address _medianizer2,
        bool _isMedian1,
        bool _isMedian2,
        bool _checkLiquidations
    ) public {
        DSTokenAbstract token = DSTokenAbstract(join.gem());

        pip.poke();
        hevm.warp(block.timestamp + 3601);
        pip.poke();
        spotter.poke(_ilk);

        // Check medianizer sources
        assertEq(pip.src(), address(token));
        assertEq(pip.orb0(), _medianizer1);
        assertEq(pip.orb1(), _medianizer2);

        // Authorization
        assertEq(join.wards(pauseProxy), 1);
        assertEq(vat.wards(address(join)), 1);
        assertEq(flip.wards(address(end)), 1);
        assertEq(flip.wards(address(flipMom)), 1);
        assertEq(pip.wards(address(osmMom)), 1);
        assertEq(pip.bud(address(spotter)), 1);
        assertEq(pip.bud(address(end)), 1);
        if (_isMedian1) assertEq(MedianAbstract(_medianizer1).bud(address(pip)), 1);
        if (_isMedian2) assertEq(MedianAbstract(_medianizer2).bud(address(pip)), 1);

        (,,,, uint256 dust) = vat.ilks(_ilk);
        dust /= RAY;
        uint256 amount = 2 * dust * WAD / getUNIV2LPPrice(address(pip));
        giveTokens(token, amount);

        assertEq(token.balanceOf(address(this)), amount);
        assertEq(vat.gem(_ilk, address(this)), 0);
        token.approve(address(join), amount);
        join.join(address(this), amount);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(vat.gem(_ilk, address(this)), amount);

        // Tick the fees forward so that art != dai in wad units
        hevm.warp(block.timestamp + 1);
        jug.drip(_ilk);

        // Deposit collateral, generate DAI
        (,uint256 rate,,,) = vat.ilks(_ilk);
        assertEq(vat.dai(address(this)), 0);
        vat.frob(_ilk, address(this), address(this), address(this), int256(amount), int256(divup(mul(RAY, dust), rate)));
        assertEq(vat.gem(_ilk, address(this)), 0);
        assertTrue(vat.dai(address(this)) >= dust * RAY && vat.dai(address(this)) <= (dust + 1) * RAY);

        // Payback DAI, withdraw collateral
        vat.frob(_ilk, address(this), address(this), address(this), -int256(amount), -int256(divup(mul(RAY, dust), rate)));
        assertEq(vat.gem(_ilk, address(this)), amount);
        assertEq(vat.dai(address(this)), 0);

        // Withdraw from adapter
        join.exit(address(this), amount);
        assertEq(token.balanceOf(address(this)), amount);
        assertEq(vat.gem(_ilk, address(this)), 0);

        // Generate new DAI to force a liquidation
        token.approve(address(join), amount);
        join.join(address(this), amount);
        // dart max amount of DAI
        (,,uint256 spotV,,) = vat.ilks(_ilk);
        vat.frob(_ilk, address(this), address(this), address(this), int256(amount), int256(mul(amount, spotV) / rate));
        hevm.warp(block.timestamp + 1);
        jug.drip(_ilk);
        assertEq(flip.kicks(), 0);
        if (_checkLiquidations) {
            cat.bite(_ilk, address(this));
            assertEq(flip.kicks(), 1);
        }

        // Dump all dai for next run
        vat.move(address(this), address(0x0), vat.dai(address(this)));
    }

    // function testCollateralIntegrations() public {
    //     vote(address(spell));
    //     scheduleWaitAndCast(address(spell));
    //     assertTrue(spell.done());

    //     // Insert new collateral tests here
    //     checkIlkIntegration(
    //         "PAXG-A",
    //         GemJoinAbstract(addr.addr("MCD_JOIN_PAXG_A")),
    //         FlipAbstract(addr.addr("MCD_FLIP_PAXG_A")),
    //         addr.addr("PIP_PAXG"),
    //         true,
    //         true,
    //         true
    //     );
    // }

    function getExtcodesize(address target) public view returns (uint256 exsize) {
        assembly {
            exsize := extcodesize(target)
        }
    }

    function testSpellIsCast_GENERAL() public {
        string memory description = new DssSpell().description();
        assertTrue(bytes(description).length > 0);
        // DS-Test can't handle strings directly, so cast to a bytes32.
        assertEq(stringToBytes32(spell.description()),
                stringToBytes32(description));

        if(address(spell) != address(spellValues.deployed_spell)) {
            assertEq(spell.expiration(), (block.timestamp + spellValues.expiration_threshold));
        } else {
            assertEq(spell.expiration(), (spellValues.deployed_spell_created + spellValues.expiration_threshold));

            // If the spell is deployed compare the on-chain bytecode size with the generated bytecode size.
            //   extcodehash doesn't match, potentially because it's address-specific, avenue for further research.
            address depl_spell = spellValues.deployed_spell;
            address code_spell = address(new DssSpell());
            assertEq(getExtcodesize(depl_spell), getExtcodesize(code_spell));
        }

        vote(address(spell));
        scheduleWaitAndCast(address(spell));
        assertTrue(spell.done());

        checkSystemValues(afterSpell);

        checkCollateralValues(afterSpell);
    }

    function testNewChainlogValues() public {
        vote(address(spell));
        scheduleWaitAndCast(address(spell));
        assertTrue(spell.done());

        ChainlogAbstract chainLog = ChainlogAbstract(addr.addr("CHANGELOG"));

        assertEq(chainLog.getAddress("MCD_CLIP_BAT_A"), addr.addr("MCD_CLIP_BAT_A"));
        assertEq(chainLog.getAddress("MCD_CLIP_CALC_BAT_A"), addr.addr("MCD_CLIP_CALC_BAT_A"));
        try chainLog.getAddress("MCD_FLIP_BAT_A") returns (address) {
            assertTrue(false);
        } catch {}

        assertEq(chainLog.getAddress("MCD_CLIP_ZRX_A"), addr.addr("MCD_CLIP_ZRX_A"));
        assertEq(chainLog.getAddress("MCD_CLIP_CALC_ZRX_A"), addr.addr("MCD_CLIP_CALC_ZRX_A"));
        try chainLog.getAddress("MCD_FLIP_ZRX_A") returns (address) {
            assertTrue(false);
        } catch {}

        assertEq(chainLog.getAddress("MCD_CLIP_KNC_A"), addr.addr("MCD_CLIP_KNC_A"));
        assertEq(chainLog.getAddress("MCD_CLIP_CALC_KNC_A"), addr.addr("MCD_CLIP_CALC_KNC_A"));
        try chainLog.getAddress("MCD_FLIP_KNC_A") returns (address) {
            assertTrue(false);
        } catch {}

        assertEq(chainLog.getAddress("MCD_CLIP_MANA_A"), addr.addr("MCD_CLIP_MANA_A"));
        assertEq(chainLog.getAddress("MCD_CLIP_CALC_MANA_A"), addr.addr("MCD_CLIP_CALC_MANA_A"));
        try chainLog.getAddress("MCD_FLIP_MANA_A") returns (address) {
            assertTrue(false);
        } catch {}


        assertEq(chainLog.getAddress("MCD_CLIP_COMP_A"), addr.addr("MCD_CLIP_COMP_A"));
        assertEq(chainLog.getAddress("MCD_CLIP_CALC_COMP_A"), addr.addr("MCD_CLIP_CALC_COMP_A"));
        try chainLog.getAddress("MCD_FLIP_COMP_A") returns (address) {
            assertTrue(false);
        } catch {}

        assertEq(chainLog.getAddress("MCD_CLIP_LRC_A"), addr.addr("MCD_CLIP_LRC_A"));
        assertEq(chainLog.getAddress("MCD_CLIP_CALC_LRC_A"), addr.addr("MCD_CLIP_CALC_LRC_A"));
        try chainLog.getAddress("MCD_FLIP_LRC_A") returns (address) {
            assertTrue(false);
        } catch {}

        assertEq(chainLog.getAddress("MCD_CLIP_BAL_A"), addr.addr("MCD_CLIP_BAL_A"));
        assertEq(chainLog.getAddress("MCD_CLIP_CALC_BAL_A"), addr.addr("MCD_CLIP_CALC_BAL_A"));
        try chainLog.getAddress("MCD_FLIP_BAL_A") returns (address) {
            assertTrue(false);
        } catch {}

        assertEq(chainLog.getAddress("MCD_CLIP_UNI_A"), addr.addr("MCD_CLIP_UNI_A"));
        assertEq(chainLog.getAddress("MCD_CLIP_CALC_UNI_A"), addr.addr("MCD_CLIP_CALC_UNI_A"));
        try chainLog.getAddress("MCD_FLIP_UNI_A") returns (address) {
            assertTrue(false);
        } catch {}

        assertEq(chainLog.getAddress("MCD_CLIP_RENBTC_A"), addr.addr("MCD_CLIP_RENBTC_A"));
        assertEq(chainLog.getAddress("MCD_CLIP_CALC_RENBTC_A"), addr.addr("MCD_CLIP_CALC_RENBTC_A"));
        try chainLog.getAddress("MCD_FLIP_RENBTC_A") returns (address) {
            assertTrue(false);
        } catch {}

        assertEq(chainLog.getAddress("MCD_CLIP_AAVE_A"), addr.addr("MCD_CLIP_AAVE_A"));
        assertEq(chainLog.getAddress("MCD_CLIP_CALC_AAVE_A"), addr.addr("MCD_CLIP_CALC_AAVE_A"));
        try chainLog.getAddress("MCD_FLIP_AAVE_A") returns (address) {
            assertTrue(false);
        } catch {}

        // This is only for kovan as we are checking keys that were wrong before only in this environment
        assertEq(chainLog.getAddress("MCD_JOIN_PSM_USDC_A"), addr.addr("MCD_JOIN_PSM_USDC_A"));
        try chainLog.getAddress("MCD_JOIN_USDC_PSM") returns (address) {
            assertTrue(false);
        } catch {}
        assertEq(chainLog.getAddress("MCD_PSM_USDC_A"), addr.addr("MCD_PSM_USDC_A"));
        try chainLog.getAddress("MCD_PSM_USDC_PSM") returns (address) {
            assertTrue(false);
        } catch {}
        assertEq(chainLog.getAddress("MCD_FLIP_PSM_USDC_A"), addr.addr("MCD_FLIP_PSM_USDC_A"));
        try chainLog.getAddress("MCD_FLIP_USDC_PSM") returns (address) {
            assertTrue(false);
        } catch {}
        //
    }

    function testFailWrongDay() public {
        require(spell.officeHours() == spellValues.office_hours_enabled);
        if (spell.officeHours()) {
            vote(address(spell));
            scheduleWaitAndCastFailDay();
        } else {
            revert("Office Hours Disabled");
        }
    }

    function testFailTooEarly() public {
        require(spell.officeHours() == spellValues.office_hours_enabled);
        if (spell.officeHours()) {
            vote(address(spell));
            scheduleWaitAndCastFailEarly();
        } else {
            revert("Office Hours Disabled");
        }
    }

    function testFailTooLate() public {
        require(spell.officeHours() == spellValues.office_hours_enabled);
        if (spell.officeHours()) {
            vote(address(spell));
            scheduleWaitAndCastFailLate();
        } else {
            revert("Office Hours Disabled");
        }
    }

    function testOnTime() public {
        vote(address(spell));
        scheduleWaitAndCast(address(spell));
    }

    function testCastCost() public {
        vote(address(spell));
        spell.schedule();

        castPreviousSpell();

        hevm.warp(spell.nextCastTime());
        uint256 startGas = gasleft();
        spell.cast();
        uint256 endGas = gasleft();
        uint256 totalGas = startGas - endGas;

        assertTrue(spell.done());
        emit log_named_uint("totalGas", totalGas);
        // Fail if cast is too expensive
        assertTrue(totalGas <= 8 * MILLION);
    }

    function liquidateIlk(bytes32 ilk, DSTokenAbstract token, GemJoinAbstract join, FlipAbstract flipper, ClipAbstract clipper, address calc, OsmAbstract pip, uint256 ilkAmt) internal {
        vote(address(spell));
        scheduleWaitAndCast(address(spell));
        assertTrue(spell.done());

        // Contracts set
        assertEq(dog.vat(), address(vat));
        assertEq(dog.vow(), address(vow));
        {
        (address clip,,,) = dog.ilks(ilk);
        assertEq(clip, address(clipper));
        }
        assertEq(clipper.ilk(), ilk);
        assertEq(clipper.vat(), address(vat));
        assertEq(clipper.vow(), address(vow));
        assertEq(clipper.dog(), address(dog));
        assertEq(clipper.spotter(), address(spotter));
        assertEq(clipper.calc(), calc);

        // Authorization
        assertEq(flipper.wards(address(cat))    , 0);
        assertEq(flipper.wards(address(flipMom)), 0);
        assertEq(vat.wards(address(clipper))    , 1);
        assertEq(dog.wards(address(clipper))    , 1);
        assertEq(clipper.wards(address(dog))    , 1);
        assertEq(clipper.wards(address(end))    , 1);
        assertEq(clipper.wards(address(clipMom)), 1);
        assertEq(clipper.wards(address(esm)), 1);

        assertEq(pip.bud(address(clipper)), 1);
        assertEq(pip.bud(address(clipMom)), 1);

        // Force max debt ceiling for BAT-A
        hevm.store(
            address(vat),
            bytes32(uint256(keccak256(abi.encode(bytes32(ilk), uint256(2)))) + 3),
            bytes32(uint256(-1))
        );

        giveTokens(token, ilkAmt);
        assertEq(token.balanceOf(address(this)), ilkAmt);

        // Join to adapter
        assertEq(vat.gem(ilk, address(this)), 0);
        token.approve(address(join), ilkAmt);
        join.join(address(this), ilkAmt);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(vat.gem(ilk, address(this)), ilkAmt);

        {
        // Generate new DAI to force a liquidation
        uint256 rate;
        int256 art;
        {
        uint256 spot;
        (,rate, spot,,) = vat.ilks(ilk);
        art = int256(mul(ilkAmt, spot) / rate);
        }

        // dart max amount of DAI
        vat.frob(ilk, address(this), address(this), address(this), int256(ilkAmt), art);
        hevm.warp(block.timestamp + 1);
        jug.drip(ilk);
        assertEq(clipper.kicks(), 0);
        dog.bark(ilk, address(this), address(this));
        assertEq(clipper.kicks(), 1);

        (, rate,,,) = vat.ilks(ilk);
        uint256 debt = mul(mul(rate, uint256(art)), dog.chop(ilk)) / WAD;
        hevm.store(
            address(vat),
            keccak256(abi.encode(address(this), uint256(5))),
            bytes32(debt)
        );
        assertEq(vat.dai(address(this)), debt);
        assertEq(vat.gem(ilk, address(this)), 0);

        hevm.warp(block.timestamp + 20 minutes);
        (, uint256 tab, uint256 lot, address usr,, uint256 top) = clipper.sales(1);

        assertEq(usr, address(this));
        assertEq(tab, debt);
        assertEq(lot, ilkAmt);
        assertTrue(mul(lot, top) > tab); // There is enough collateral to cover the debt at current price

        vat.hope(address(clipper));
        clipper.take(1, lot, top, address(this), bytes(""));
        }

        {
        (, uint256 tab, uint256 lot, address usr,,) = clipper.sales(1);
        assertEq(usr, address(0));
        assertEq(tab, 0);
        assertEq(lot, 0);
        assertEq(vat.dai(address(this)), 0);
        assertEq(vat.gem(ilk, address(this)), ilkAmt); // What was purchased + returned back as it is the owner of the vault
        }
    }

    function testSpellIsCast_BAT_A_clip() public {
        liquidateIlk(
            "BAT-A",
            DSTokenAbstract(addr.addr("BAT")),
            GemJoinAbstract(addr.addr("MCD_JOIN_BAT_A")),
            FlipAbstract(addr.addr("MCD_FLIP_BAT_A")),
            ClipAbstract(addr.addr("MCD_CLIP_BAT_A")),
            addr.addr("MCD_CLIP_CALC_BAT_A"),
            OsmAbstract(addr.addr("PIP_BAT")),
            2000 * WAD
        );
    }

    function testSpellIsCast_ZRX_A_clip() public {
        liquidateIlk(
            "ZRX-A",
            DSTokenAbstract(addr.addr("ZRX")),
            GemJoinAbstract(addr.addr("MCD_JOIN_ZRX_A")),
            FlipAbstract(addr.addr("MCD_FLIP_ZRX_A")),
            ClipAbstract(addr.addr("MCD_CLIP_ZRX_A")),
            addr.addr("MCD_CLIP_CALC_ZRX_A"),
            OsmAbstract(addr.addr("PIP_ZRX")),
            2000 * WAD
        );
    }

    function testSpellIsCast_KNC_A_clip() public {
        liquidateIlk(
            "KNC-A",
            DSTokenAbstract(addr.addr("KNC")),
            GemJoinAbstract(addr.addr("MCD_JOIN_KNC_A")),
            FlipAbstract(addr.addr("MCD_FLIP_KNC_A")),
            ClipAbstract(addr.addr("MCD_CLIP_KNC_A")),
            addr.addr("MCD_CLIP_CALC_KNC_A"),
            OsmAbstract(addr.addr("PIP_KNC")),
            1000 * WAD
        );
    }

    function testSpellIsCast_MANA_A_clip() public {
        liquidateIlk(
            "MANA-A",
            DSTokenAbstract(addr.addr("MANA")),
            GemJoinAbstract(addr.addr("MCD_JOIN_MANA_A")),
            FlipAbstract(addr.addr("MCD_FLIP_MANA_A")),
            ClipAbstract(addr.addr("MCD_CLIP_MANA_A")),
            addr.addr("MCD_CLIP_CALC_MANA_A"),
            OsmAbstract(addr.addr("PIP_MANA")),
            2000 * WAD
        );
    }

    function testSpellIsCast_COMP_A_clip() public {
        liquidateIlk(
            "COMP-A",
            DSTokenAbstract(addr.addr("COMP")),
            GemJoinAbstract(addr.addr("MCD_JOIN_COMP_A")),
            FlipAbstract(addr.addr("MCD_FLIP_COMP_A")),
            ClipAbstract(addr.addr("MCD_CLIP_COMP_A")),
            addr.addr("MCD_CLIP_CALC_COMP_A"),
            OsmAbstract(addr.addr("PIP_COMP")),
            4 * WAD
        );
    }

    function testSpellIsCast_LRC_A_clip() public {
        liquidateIlk(
            "LRC-A",
            DSTokenAbstract(addr.addr("LRC")),
            GemJoinAbstract(addr.addr("MCD_JOIN_LRC_A")),
            FlipAbstract(addr.addr("MCD_FLIP_LRC_A")),
            ClipAbstract(addr.addr("MCD_CLIP_LRC_A")),
            addr.addr("MCD_CLIP_CALC_LRC_A"),
            OsmAbstract(addr.addr("PIP_LRC")),
            4000 * WAD
        );
    }

    function testSpellIsCast_BAL_A_clip() public {
        liquidateIlk(
            "BAL-A",
            DSTokenAbstract(addr.addr("BAL")),
            GemJoinAbstract(addr.addr("MCD_JOIN_BAL_A")),
            FlipAbstract(addr.addr("MCD_FLIP_BAL_A")),
            ClipAbstract(addr.addr("MCD_CLIP_BAL_A")),
            addr.addr("MCD_CLIP_CALC_BAL_A"),
            OsmAbstract(addr.addr("PIP_BAL")),
            50 * WAD
        );
    }

    function testSpellIsCast_UNI_A_clip() public {
        liquidateIlk(
            "UNI-A",
            DSTokenAbstract(addr.addr("UNI")),
            GemJoinAbstract(addr.addr("MCD_JOIN_UNI_A")),
            FlipAbstract(addr.addr("MCD_FLIP_UNI_A")),
            ClipAbstract(addr.addr("MCD_CLIP_UNI_A")),
            addr.addr("MCD_CLIP_CALC_UNI_A"),
            OsmAbstract(addr.addr("PIP_UNI")),
            100 * WAD
        );
    }

    function testSpellIsCast_RENBTC_A_clip() public {
        liquidateIlk(
            "RENBTC-A",
            DSTokenAbstract(addr.addr("RENBTC")),
            GemJoinAbstract(addr.addr("MCD_JOIN_RENBTC_A")),
            FlipAbstract(addr.addr("MCD_FLIP_RENBTC_A")),
            ClipAbstract(addr.addr("MCD_CLIP_RENBTC_A")),
            addr.addr("MCD_CLIP_CALC_RENBTC_A"),
            OsmAbstract(addr.addr("PIP_RENBTC")),
            0.05 * 10 ** 18
        );
    }

    function testSpellIsCast_AAVE_A_clip() public {
        liquidateIlk(
            "AAVE-A",
            DSTokenAbstract(addr.addr("AAVE")),
            GemJoinAbstract(addr.addr("MCD_JOIN_AAVE_A")),
            FlipAbstract(addr.addr("MCD_FLIP_AAVE_A")),
            ClipAbstract(addr.addr("MCD_CLIP_AAVE_A")),
            addr.addr("MCD_CLIP_CALC_AAVE_A"),
            OsmAbstract(addr.addr("PIP_AAVE")),
            10 * WAD
        );
    }

    function testClipperMomSetBreaker() public {
        vote(address(spell));
        scheduleWaitAndCast(address(spell));
        assertTrue(spell.done());

        // clipperMom is an authority-based contract, so here we set the Chieftain's hat
        //  to the current contract to simulate governance authority.
        hevm.store(
            address(chief),
            bytes32(uint256(12)),
            bytes32(uint256(address(this)))
        );

        ClipAbstract clipBATA = ClipAbstract(addr.addr("MCD_CLIP_BAT_A"));
        assertEq(clipBATA.stopped(), 0);
        clipMom.setBreaker(address(clipBATA), 1, 0);
        assertEq(clipBATA.stopped(), 1);
        clipMom.setBreaker(address(clipBATA), 2, 0);
        assertEq(clipBATA.stopped(), 2);
        clipMom.setBreaker(address(clipBATA), 3, 0);
        assertEq(clipBATA.stopped(), 3);
        clipMom.setBreaker(address(clipBATA), 0, 0);
        assertEq(clipBATA.stopped(), 0);

        ClipAbstract clipZRXA = ClipAbstract(addr.addr("MCD_CLIP_ZRX_A"));
        assertEq(clipZRXA.stopped(), 0);
        clipMom.setBreaker(address(clipZRXA), 1, 0);
        assertEq(clipZRXA.stopped(), 1);
        clipMom.setBreaker(address(clipZRXA), 2, 0);
        assertEq(clipZRXA.stopped(), 2);
        clipMom.setBreaker(address(clipZRXA), 3, 0);
        assertEq(clipZRXA.stopped(), 3);
        clipMom.setBreaker(address(clipZRXA), 0, 0);
        assertEq(clipZRXA.stopped(), 0);
    }

    function testClipperMomTripBreaker() public {
        vote(address(spell));
        scheduleWaitAndCast(address(spell));
        assertTrue(spell.done());

        // Hacking nxt price to 0x123 (and making it valid)
        bytes32 hackedValue = 0x0000000000000000000000000000000100000000000000000000000000000123;

        ClipAbstract clipBATA = ClipAbstract(addr.addr("MCD_CLIP_BAT_A"));
        hevm.store(address(addr.addr("PIP_BAT")), bytes32(uint256(4)), hackedValue);
        assertEq(clipMom.tolerance(address(clipBATA)), (RAY / 2)); // (RAY / 2) for 50%
        // Price is hacked, anyone can trip the breaker
        clipMom.tripBreaker(address(clipBATA));
        assertEq(clipBATA.stopped(), 2);

        ClipAbstract clipZRXA = ClipAbstract(addr.addr("MCD_CLIP_ZRX_A"));
        hevm.store(address(addr.addr("PIP_ZRX")), bytes32(uint256(4)), hackedValue);
        assertEq(clipMom.tolerance(address(clipZRXA)), (RAY / 2)); // (RAY / 2) for 50%
        // Price is hacked, anyone can trip the breaker
        clipMom.tripBreaker(address(clipZRXA));
        assertEq(clipZRXA.stopped(), 2);
    }

    function testSpellIsCast_End() public {
        vote(address(spell));
        scheduleWaitAndCast(address(spell));
        assertTrue(spell.done());

        DSTokenAbstract BAT = DSTokenAbstract(addr.addr("BAT"));
        GemJoinAbstract joinBATA = GemJoinAbstract(addr.addr("MCD_JOIN_BAT_A"));
        ClipAbstract clipBATA = ClipAbstract(addr.addr("MCD_CLIP_BAT_A"));

        DSTokenAbstract ZRX = DSTokenAbstract(addr.addr("ZRX"));
        GemJoinAbstract joinZRXA = GemJoinAbstract(addr.addr("MCD_JOIN_ZRX_A"));
        ClipAbstract clipZRXA = ClipAbstract(addr.addr("MCD_CLIP_ZRX_A"));

        // Force max debt ceiling for collaterals
        hevm.store(
            address(vat),
            bytes32(uint256(keccak256(abi.encode(bytes32("BAT-A"), uint256(2)))) + 3),
            bytes32(uint256(-1))
        );
        hevm.store(
            address(vat),
            bytes32(uint256(keccak256(abi.encode(bytes32("ZRX-B"), uint256(2)))) + 3),
            bytes32(uint256(-1))
        );

        {
            uint256 BATIlkAmt = 2000 * WAD;
            uint256 ZRXIlkAmt = 2000 * WAD;

            giveTokens(BAT, BATIlkAmt * 3);
            giveTokens(ZRX, ZRXIlkAmt);

            BAT.approve(address(joinBATA), BATIlkAmt);
            joinBATA.join(address(this), BATIlkAmt);

            ZRX.approve(address(joinZRXA), ZRXIlkAmt);
            joinZRXA.join(address(this), ZRXIlkAmt);

            (,uint256 rate, uint256 spot,,) = vat.ilks("BAT-A");
            vat.frob("BAT-A", address(this), address(this), address(this), int256(BATIlkAmt), int256(mul(BATIlkAmt, spot) / rate));

            (, rate, spot,,) = vat.ilks("ZRX-A");
            vat.frob("ZRX-A", address(this), address(this), address(this), int256(ZRXIlkAmt), int256(mul(ZRXIlkAmt, spot) / rate));
        }

        hevm.warp(block.timestamp + 1);
        jug.drip("BAT-A");
        jug.drip("ZRX-A");

        uint256 auctionIdBATA = clipBATA.kicks() + 1;
        uint256 auctionIdZRXA = clipZRXA.kicks() + 1;

        dog.bark("BAT-A", address(this), address(this));
        dog.bark("ZRX-A", address(this), address(this));

        assertEq(clipBATA.kicks(), auctionIdBATA);
        assertEq(clipZRXA.kicks(), auctionIdZRXA);

        hevm.store(
            address(end),
            keccak256(abi.encode(address(this), uint256(0))),
            bytes32(uint256(1))
        );
        assertEq(end.wards(address(this)), 1);

        end.cage();
        end.cage("BAT-A");
        end.cage("ZRX-A");

        (,,, address usr,,) = clipBATA.sales(auctionIdBATA);
        assertTrue(usr != address(0));

        (,,, usr,,) = clipZRXA.sales(auctionIdZRXA);
        assertTrue(usr != address(0));

        end.snip("BAT-A", auctionIdBATA);
        (,,, usr,,) = clipBATA.sales(auctionIdBATA);
        assertTrue(usr == address(0));

        end.snip("ZRX-A", auctionIdZRXA);
        (,,, usr,,) = clipZRXA.sales(auctionIdZRXA);
        assertTrue(usr == address(0));

        end.skim("BAT-A", address(this));
        end.skim("ZRX-A", address(this));

        end.free("BAT-A");
        end.free("ZRX-A");

        hevm.warp(block.timestamp + end.wait());

        vow.heal(min(vat.dai(address(vow)), sub(sub(vat.sin(address(vow)), vow.Sin()), vow.Ash())));

        // Removing the surplus to allow continuing the execution.
        // (not needed if enough vaults skimmed)
        // hevm.store(
        //     address(vat),
        //     keccak256(abi.encode(address(vow), uint256(5))),
        //     bytes32(uint256(0))
        // );

        end.thaw();

        end.flow("BAT-A");
        end.flow("ZRX-A");

        vat.hope(address(end));

        uint256 daiToRedeem = vat.dai(address(this)) / RAY;
        assertTrue(daiToRedeem > 0);

        end.pack(daiToRedeem);

        // Force a lot of collateral available to pay in end.cash
        hevm.store(
            address(vat),
            keccak256(abi.encode(address(end), keccak256(abi.encode(bytes32("BAT-A"), uint256(4))))),
            bytes32(uint256(1 * MILLION * WAD))
        );
        hevm.store(
            address(vat),
            keccak256(abi.encode(address(end), keccak256(abi.encode(bytes32("ZRX-A"), uint256(4))))),
            bytes32(uint256(1 * MILLION * WAD))
        );


        end.cash("BAT-A", daiToRedeem);
        end.cash("ZRX-A", daiToRedeem);
    }
}
