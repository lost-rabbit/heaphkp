-- PhoenixXI HNM / endgame boss table for a DKP / ToD addon.
-- Built ONLY from Phoenix server code: phoenixffxi/Phoenix branch live @ ed41f351f6 (2026-10-30).
-- Paths below are relative to the repo root. Scope: RoZ / CoP / ToAU only (phoenix_scope.py).
--
-- Global rules that apply to every timed entry (do not repeat per row):
--  * Restart persistence: modules/phoenix/lua/custom/pxi_timed_nm_respawn_persistence.lua saves each pending
--    respawn deadline in a server variable on despawn and restores it at boot (floor 60 s). So a restart does NOT
--    re-roll a dead NM's ToD. Exception (file header, lines 10-12): an NM that is ALIVE at the restart has no saved
--    deadline and gets its onMobInitialize roll again (the "boot" value in each note).
--  * minS/maxS are seconds from ToD (despawn) to the earliest/latest spawn. windowS = step size when the roll is
--    quantised (spawn can only land on min + n*windowS); nil = continuous random.
--  * Mob names: the server strips apostrophes from internal names (GuDha_Effigy, ZaDha_Adamantking). The names
--    below re-add them the way the client prints them; that is the only part not literally in the code.
--  * era/... modules gated by xi.pre(xi.expansion.SOA) only run while SoA content is off. Live settings are not in
--    the repo; Phoenix's hard line says SoA is off, so they are treated as active.

return {
    ---------------------------------------------------------------------------
    -- Land Kings: FORCE-POP on Phoenix (no ToD). The era timed-pop system is disabled:
    -- modules/era/lua/globals/era_hnm_system.lua:24 hnmSystem:setEnabled(false); custom_hnm_system is not in init.txt.
    -- Phoenix re-shows the ??? NPCs: modules/phoenix/lua/zones/npc_visibility.lua:74,102,190.
    ---------------------------------------------------------------------------
    { name = 'Fafnir', zone = "Dragon's Aery", group = 'HNM', forced = true, hq = 'Nidhogg',
      pop = 'Jug of Honey Wine (trade to ??? qm_fafnir)',
      hqRule = 'separate pop: Cup of Sweet Tea at the same ??? (Fafnir drops it, uncommon)',
      note = '??? hides 30 s after a pop; neither can pop while the other is up',
      src = 'scripts/zones/Dragons_Aery/npcs/qm_fafnir.lua:18' },
    { name = 'Nidhogg', zone = "Dragon's Aery", group = 'HNM', forced = true, sharesWith = 'Fafnir',
      pop = 'Cup of Sweet Tea (trade to ??? qm_fafnir)',
      note = 'shares the ??? with Fafnir; no shared timer because both are force-pop',
      src = 'scripts/zones/Dragons_Aery/npcs/qm_fafnir.lua:23' },
    { name = 'Adamantoise', zone = 'Valley of Sorrows', group = 'HNM', forced = true, hq = 'Aspidochelone',
      pop = 'Clump of Blue Pondweed (trade to ??? qm_adamantoise)',
      hqRule = 'separate pop: Clump of Red Pondweed at the same ???',
      src = 'scripts/zones/Valley_of_Sorrows/npcs/qm_adamantoise.lua:18' },
    { name = 'Aspidochelone', zone = 'Valley of Sorrows', group = 'HNM', forced = true, sharesWith = 'Adamantoise',
      pop = 'Clump of Red Pondweed (trade to ??? qm_adamantoise)',
      src = 'scripts/zones/Valley_of_Sorrows/npcs/qm_adamantoise.lua:23' },
    { name = 'Behemoth', zone = "Behemoth's Dominion", group = 'HNM', forced = true, hq = 'King Behemoth',
      pop = 'Beastly Shank (trade to ??? qm_behemoth)',
      hqRule = 'separate pop: Savory Shank at the same ???',
      src = 'scripts/zones/Behemoths_Dominion/npcs/qm_behemoth.lua:18' },
    { name = 'King Behemoth', zone = "Behemoth's Dominion", group = 'HNM', forced = true, sharesWith = 'Behemoth',
      pop = 'Savory Shank (trade to ??? qm_behemoth)',
      src = 'scripts/zones/Behemoths_Dominion/npcs/qm_behemoth.lua:23' },

    ---------------------------------------------------------------------------
    -- Timed HNMs / LS NMs (open world)
    ---------------------------------------------------------------------------
    { name = 'King Arthro', zone = 'Jugner Forest', group = 'HNM', minS = 75900, maxS = 86700, windowS = 1800, forced = false,
      note = 'timer is on the 10 Knight Crabs (75900 + 0..6 x 1800); kill all 10 crabs and King Arthro pops. Boot (no save): crabs 900-11700 s in 30-min steps',
      src = 'scripts/zones/Jugner_Forest/mobs/King_Arthro.lua:94' },
    { name = 'Simurgh', zone = 'Rolanberry Fields', group = 'HNM', minS = 75600, maxS = 86400, forced = false,
      note = 'era old-timer module replaces base 1-2 h; same roll at boot',
      src = 'modules/era/lua/globals/old_nm_respawn_timers.lua:53' },
    { name = 'Roc', zone = 'Sauromugue Champaign', group = 'HNM', minS = 75600, maxS = 86400, forced = false,
      note = 'era old-timer module replaces base 1-2 h; same roll at boot',
      src = 'modules/era/lua/globals/old_nm_respawn_timers.lua:49' },
    { name = 'Serket', zone = 'Garlaige Citadel', group = 'HNM', minS = 75600, maxS = 86400, forced = false,
      note = 'same roll at boot; Phoenix only changes model/animations (original_serket.lua)',
      src = 'scripts/zones/Garlaige_Citadel/mobs/Serket.lua:66' },
    { name = 'Bloodsucker', zone = 'Bostaunieux Oubliette', group = 'HNM', minS = 259200, maxS = 259200, forced = false,
      note = 'Bloodsucker_NM (lv70-73 NM, not the 300 s trash leech of the same name). Fixed 72 h, also at boot',
      src = 'modules/era/lua/globals/old_nm_respawn_timers.lua:56' },
    { name = 'Vrtra', zone = "King Ranperre's Tomb", group = 'HNM', minS = 259200, maxS = 432000, windowS = 1800, forced = false,
      note = '144-240 x 1800 s (3-5 days in 30-min steps); same roll at boot',
      src = 'scripts/zones/King_Ranperres_Tomb/mobs/Vrtra.lua:170' },
    { name = 'Ash Dragon', zone = "Ifrit's Cauldron", group = 'HNM', minS = 259200, maxS = 432000, forced = false,
      note = '3-5 days continuous; same roll at boot',
      src = 'scripts/zones/Ifrits_Cauldron/mobs/Ash_Dragon.lua:52' },
    { name = 'Cactrot Rapido', zone = 'Eastern Altepa Desert', group = 'NM', minS = 172800, maxS = 259200, forced = false,
      note = '2-3 days; same roll at boot',
      src = 'scripts/zones/Eastern_Altepa_Desert/mobs/Cactrot_Rapido.lua:146' },
    { name = 'Guivre', zone = 'Kuftal Tunnel', group = 'HNM', minS = 64800, maxS = 86400, forced = false,
      note = '18-24 h, random spawn point; boot 900-10800 s',
      src = 'scripts/zones/Kuftal_Tunnel/mobs/Guivre.lua:279' },
    { name = 'Shikigami Weapon', zone = "Ro'Maeve", group = 'NM', minS = 76500, maxS = 76500, forced = false,
      note = 'fixed yaml respawn 76500 (21 h 15 m); no script roll; spawns invisible and patrols',
      src = 'data/zones/romaeve/mobs.yaml:683' },
    { name = 'King Vinegarroon', zone = 'Western Altepa Desert', group = 'HNM', minS = 75600, maxS = 75600, forced = false,
      note = 'window opens 21 h after ToD, then needs EARTH weather (dust/sand storm); Phoenix holds him at boot until a weather change',
      src = 'scripts/zones/Western_Altepa_Desert/mobs/King_Vinegarroon.lua:130' },
    { name = 'Kreutzet', zone = 'Cape Teriggan', group = 'NM', minS = 32400, maxS = 43200, forced = false,
      note = '9-12 h, then needs WIND weather; pops 30-150 s after wind starts (Zone.lua:54); same roll at boot',
      src = 'scripts/zones/Cape_Teriggan/mobs/Kreutzet.lua:84' },

    -- Beastmen kings: NQ/HQ lottery, shared ToD, counters in server vars (survive restarts)
    { name = 'Yagudo Avatar', zone = 'Castle Oztroja', group = 'NM', minS = 77400, maxS = 86400, windowS = 1800, forced = false,
      hq = 'Tzee Xicu the Manifest',
      hqRule = 'on NQ despawn: kills = [PH] count+1; HQ takes the next window if kills>=7, or kills>=2 and 20% roll, AND 3 days have passed since last HQ kill ([POP] var). Else NQ again',
      note = 'NQ->next: 75600 + 1..6 x 1800. After an HQ kill the NQ returns in 75600-86400 (continuous). Boot (no save) NQ 900-10800 s',
      src = 'scripts/zones/Castle_Oztroja/mobs/Yagudo_Avatar.lua:95' },
    { name = 'Tzee Xicu the Manifest', zone = 'Castle Oztroja', group = 'NM', minS = 75600, maxS = 86400, forced = false,
      sharesWith = 'Yagudo Avatar',
      note = 'HQ kill resets [PH] counter, locks HQ for 259200 s, NQ back in 75600-86400',
      src = 'scripts/zones/Castle_Oztroja/mobs/Tzee_Xicu_the_Manifest.lua:108' },
    { name = 'Orcish Overlord', zone = 'Monastic Cavern', group = 'NM', minS = 77400, maxS = 86400, windowS = 1800, forced = false,
      hq = 'Overlord Bakgodek',
      hqRule = 'same as Yagudo Avatar: kills>=7, or >=2 with 20%, and 3-day HQ lockout ([POP]Overlord_Bakgodek)',
      note = 'quest copies (UNDERSTANDING_OVERLORD) do not count. Boot NQ 77400-86400 in 30-min steps',
      src = 'scripts/zones/Monastic_Cavern/mobs/Orcish_Overlord.lua:55' },
    { name = 'Overlord Bakgodek', zone = 'Monastic Cavern', group = 'NM', minS = 75600, maxS = 86400, forced = false,
      sharesWith = 'Orcish Overlord',
      note = 'HQ kill resets counter, 3-day HQ lockout, NQ back in 75600-86400',
      src = 'scripts/zones/Monastic_Cavern/mobs/Overlord_Bakgodek.lua:43' },
    { name = 'Diamond Quadav', zone = 'Qulun Dome', group = 'NM', minS = 77400, maxS = 86400, windowS = 1800, forced = false,
      hq = "Za'Dha Adamantking",
      hqRule = 'same as Yagudo Avatar: kills>=7, or >=2 with 20%, and 3-day HQ lockout ([POP]Za_Dha_Adamantking)',
      note = 'quest copies do not count. Boot NQ 77400-86400 in 30-min steps',
      src = 'scripts/zones/Qulun_Dome/mobs/Diamond_Quadav.lua:43' },
    { name = "Za'Dha Adamantking", zone = 'Qulun Dome', group = 'NM', minS = 75600, maxS = 86400, forced = false,
      sharesWith = 'Diamond Quadav',
      note = 'HQ kill resets counter, 3-day HQ lockout, NQ back in 75600-86400',
      src = 'scripts/zones/Qulun_Dome/mobs/ZaDha_Adamantking.lua:47' },

    ---------------------------------------------------------------------------
    -- CoP timed
    ---------------------------------------------------------------------------
    { name = 'Tiamat', zone = 'Attohwa Chasm', group = 'CoP', minS = 259200, maxS = 432000, windowS = 1800, forced = false,
      note = '144-240 x 1800 s (3-5 days in 30-min steps); same roll at boot',
      src = 'scripts/zones/Attohwa_Chasm/mobs/Tiamat.lua:226' },
    { name = 'Jormungand', zone = 'Uleguerand Range', group = 'CoP', minS = 259200, maxS = 432000, windowS = 1800, forced = false,
      note = '144-240 x 1800 s (3-5 days in 30-min steps); same roll at boot',
      src = 'scripts/zones/Uleguerand_Range/mobs/Jormungand.lua:229' },
    { name = 'Xolotl', zone = 'Attohwa Chasm', group = 'CoP', minS = 75600, maxS = 86400, forced = false,
      note = 'night-only spawn type (yaml at_night, mobs.yaml:1715): pops at night once the window is open. Long timer only if KILLED; a dawn despawn resets to 1 s. Same roll at boot',
      src = 'scripts/zones/Attohwa_Chasm/mobs/Xolotl.lua:120' },

    ---------------------------------------------------------------------------
    -- ToAU timed
    ---------------------------------------------------------------------------
    { name = 'Cerberus', zone = 'Mount Zhayolm', group = 'ToAU', minS = 172800, maxS = 259200, windowS = 3600, forced = false,
      note = '48-72 x 3600 s (1-hour steps); same roll at boot',
      src = 'scripts/zones/Mount_Zhayolm/mobs/Cerberus.lua:173' },
    { name = 'Hydra', zone = 'Wajaom Woodlands', group = 'ToAU', minS = 172800, maxS = 259200, windowS = 3600, forced = false,
      note = '48-72 x 3600 s (1-hour steps); same roll at boot',
      src = 'scripts/zones/Wajaom_Woodlands/mobs/Hydra.lua:166' },
    { name = 'Khimaira', zone = 'Caedarva Mire', group = 'ToAU', minS = 172800, maxS = 259200, windowS = 3600, forced = false,
      note = '48-72 x 3600 s (1-hour steps); Phoenix moves him back to his original bowl (phoenix caedarva_mire/mobs.yaml:171, pxi_nm_spawn_points.lua)',
      src = 'scripts/zones/Caedarva_Mire/mobs/Khimaira.lua:136' },

    ---------------------------------------------------------------------------
    -- Sky (RoZ)
    ---------------------------------------------------------------------------
    { name = 'Faust', zone = "The Shrine of Ru'Avitau", group = 'Sky', minS = 10800, maxS = 21600, forced = false,
      note = '3-6 h after kill; at boot uses yaml base 10800',
      src = 'scripts/zones/The_Shrine_of_RuAvitau/mobs/Faust.lua:107' },
    { name = 'Mother Globe', zone = "The Shrine of Ru'Avitau", group = 'Sky', minS = 10800, maxS = 21600, forced = false,
      note = '3-6 h after kill; at boot uses yaml base 10800',
      src = 'scripts/zones/The_Shrine_of_RuAvitau/mobs/Mother_Globe.lua:284' },
    { name = 'Zipacna', zone = "Ve'Lugannon Palace", group = 'Sky', minS = 10800, maxS = 21600, forced = false,
      note = '3-6 h after kill; at boot uses yaml base 10800',
      src = 'scripts/zones/VeLugannon_Palace/mobs/Zipacna.lua:408' },
    { name = 'Steam Cleaner', zone = "Ve'Lugannon Palace", group = 'Sky', minS = 7200, maxS = 7200, forced = false,
      note = 'lottery, not a fixed pop: after 2 h, each eligible Detector repop has a 10% chance to be Steam Cleaner (Detector.lua:291). maxS = lottery open, not a guarantee',
      src = 'scripts/zones/VeLugannon_Palace/mobs/Steam_Cleaner.lua:25' },
    { name = 'Genbu', zone = "Ru'Aun Gardens", group = 'Sky', forced = true, pop = 'Gem of the North + Winterstone (???  qm1)',
      src = 'scripts/zones/RuAun_Gardens/npcs/qm1.lua:14' },
    { name = 'Seiryu', zone = "Ru'Aun Gardens", group = 'Sky', forced = true, pop = 'Gem of the East + Springstone (??? qm2)',
      src = 'scripts/zones/RuAun_Gardens/npcs/qm2.lua:14' },
    { name = 'Byakko', zone = "Ru'Aun Gardens", group = 'Sky', forced = true, pop = 'Gem of the West + Autumnstone (??? qm3)',
      src = 'scripts/zones/RuAun_Gardens/npcs/qm3.lua:14' },
    { name = 'Suzaku', zone = "Ru'Aun Gardens", group = 'Sky', forced = true, pop = 'Gem of the South + Summerstone (??? qm4)',
      src = 'scripts/zones/RuAun_Gardens/npcs/qm4.lua:14' },
    { name = 'Kirin', zone = "The Shrine of Ru'Avitau", group = 'Sky', forced = true,
      pop = 'Seal of Genbu + Seal of Byakko + Seal of Seiryu + Seal of Suzaku (??? qm2, pops claimed to trader)',
      note = "the Ru'Aun Gardens Kirin is TVR content (Strange Happenings) and not in scope",
      src = 'scripts/zones/The_Shrine_of_RuAvitau/npcs/qm2.lua:12' },
    { name = 'Ullikummi', zone = "The Shrine of Ru'Avitau", group = 'Sky', forced = true, pop = 'Chunk of Diorite (??? qm3)',
      src = 'scripts/zones/The_Shrine_of_RuAvitau/npcs/qm3.lua:13' },

    ---------------------------------------------------------------------------
    -- Sea (CoP). Absolute Virtue left out: Phoenix disables its spawn
    -- (modules/phoenix/lua/zones/AlTaieu/mobs/disable_av_spawn.lua:10).
    ---------------------------------------------------------------------------
    { name = 'Jailer of Hope', zone = "Al'Taieu", group = 'Sea', forced = true,
      pop = 'First Virtue + Deed of Placidity + HQ Phuabo Organ', src = 'scripts/zones/AlTaieu/npcs/qm_jailer_of_hope.lua:14' },
    { name = 'Jailer of Justice', zone = "Al'Taieu", group = 'Sea', forced = true,
      pop = 'Second Virtue + Deed of Moderation + HQ Xzomit Organ', src = 'scripts/zones/AlTaieu/npcs/qm_jailer_of_justice.lua:14' },
    { name = 'Jailer of Prudence', zone = "Al'Taieu", group = 'Sea', forced = true,
      pop = 'Third Virtue + Deed of Sensibility + HQ Hpemde Organ', note = 'pops two Jailers of Prudence',
      src = 'scripts/zones/AlTaieu/npcs/qm_jailer_of_prudence.lua:14' },
    { name = 'Jailer of Love', zone = "Al'Taieu", group = 'Sea', forced = true,
      pop = 'Fourth Virtue + Fifth Virtue + Sixth Virtue', note = 'AV follow-up disabled on Phoenix',
      src = 'scripts/zones/AlTaieu/npcs/qm_jailer_of_love.lua:16' },
    { name = 'Jailer of Faith', zone = "The Garden of Ru'Hmet", group = 'Sea', forced = true,
      pop = 'HQ Euvhi Organ (??? moves between 5 spots after each kill)', src = 'scripts/zones/The_Garden_of_RuHmet/npcs/qm_jailer_of_faith.lua:18' },
    { name = 'Jailer of Fortitude', zone = "The Garden of Ru'Hmet", group = 'Sea', forced = true,
      pop = '12x Ghrah M Chip (??? moves between 5 spots after each kill)', src = 'scripts/zones/The_Garden_of_RuHmet/npcs/qm_jailer_of_fortitude.lua:18' },
    { name = 'Jailer of Temperance', zone = "Grand Palace of Hu'Xzoi", group = 'Sea', minS = 900, maxS = 900, forced = false,
      note = "PH lottery: killing the currently picked Eo'zdei (PH re-picked every 15 min) pops him if 15 min have passed since his last death. Cooldown is a local var: resets on restart",
      src = 'scripts/zones/Grand_Palace_of_HuXzoi/mobs/Jailer_of_Temperance.lua:192' },

    ---------------------------------------------------------------------------
    -- CoP battlefields (forced)
    ---------------------------------------------------------------------------
    { name = 'Ouryu', zone = 'Riverne - Site #A01', group = 'CoP', forced = true, pop = 'Cloud Evoker (BCNM Ouryu Cometh, 18 players, 60 min)',
      src = 'scripts/battlefields/Riverne_Site_A01/ouryu_cometh.lua:17' },
    { name = 'Bahamut', zone = 'Riverne - Site #B01', group = 'CoP', forced = true, pop = "Monarch's Orb (Wyrmking Descends, 18 players, 60 min)",
      note = 'entry needs the Jeuno quest Storms of Fate completed', src = 'scripts/battlefields/Riverne_Site_B01/wyrmking_descends.lua:15' },

    ---------------------------------------------------------------------------
    -- Dynamis (all 10 areas registered by modules/phoenix/dynamis/lua/dynamis_overrides.lua:38-49).
    -- Entry: Timeless Hourglass 1,000,000 gil (settings_era.lua:16), 3-day re-entry (:12), 60 min (:13).
    -- Live DYNA level min / lockout settings are not in the repo.
    ---------------------------------------------------------------------------
    { name = "Overlord's Tombstone", zone = "Dynamis - San d'Oria", group = 'Dynamis', forced = true, pop = 'Timeless Hourglass',
      src = 'modules/phoenix/dynamis/lua/dynamis_overrides.lua:73' },
    { name = "Gu'Dha Effigy", zone = 'Dynamis - Bastok', group = 'Dynamis', forced = true, pop = 'Timeless Hourglass',
      src = 'modules/phoenix/dynamis/lua/dynamis_overrides.lua:102' },
    { name = 'Tzee Xicu Idol', zone = 'Dynamis - Windurst', group = 'Dynamis', forced = true, pop = 'Timeless Hourglass',
      src = 'modules/phoenix/dynamis/lua/dynamis_overrides.lua:132' },
    { name = 'Goblin Golem', zone = 'Dynamis - Jeuno', group = 'Dynamis', forced = true, pop = 'Timeless Hourglass',
      src = 'modules/phoenix/dynamis/lua/dynamis_overrides.lua:163' },
    { name = 'Angra Mainyu', zone = 'Dynamis - Beaucedine', group = 'Dynamis', forced = true, pop = 'Timeless Hourglass',
      src = 'modules/phoenix/dynamis/lua/dynamis_overrides.lua:220' },
    { name = 'Dynamis Lord', zone = 'Dynamis - Xarcabard', group = 'Dynamis', forced = true, pop = 'Timeless Hourglass',
      note = 'phoenix_scope.zone_ok wrongly blocks "dynamis_xarcabard" (Dynamis Divergence regex); the zone is live',
      src = 'modules/phoenix/dynamis/lua/dynamis_overrides.lua:388' },
    { name = 'Cirrate Christelle', zone = 'Dynamis - Valkurm', group = 'Dynamis', forced = true, pop = 'Timeless Hourglass (Hieroglyphics entry)',
      src = 'modules/phoenix/dynamis/lua/dynamis_overrides.lua:468' },
    { name = 'Apocalyptic Beast', zone = 'Dynamis - Buburimu', group = 'Dynamis', forced = true, pop = 'Timeless Hourglass (Hieroglyphics entry)',
      src = 'modules/phoenix/dynamis/lua/dynamis_overrides.lua:552' },
    { name = 'Antaeus', zone = 'Dynamis - Qufim', group = 'Dynamis', forced = true, pop = 'Timeless Hourglass (Hieroglyphics entry)',
      src = 'modules/phoenix/dynamis/lua/dynamis_overrides.lua:666' },
    { name = 'Dynamis-Tavnazia', zone = 'Dynamis - Tavnazia', group = 'Dynamis', forced = true, pop = 'Timeless Hourglass (Hieroglyphics entry)',
      manual = true,
      note = 'run-level event: the Phoenix mob table names no BOSS for Tavnazia (Nightmare Bugard/Antlion/Worm are tagged "Boss" in dynamis_mobs_tav.lua:267). Log the run manually. 15-min base limit (settings_era.lua:14)',
      src = 'modules/phoenix/dynamis/lua/dynamis_overrides.lua:758' },

    ---------------------------------------------------------------------------
    -- Limbus (legacy Lv75 layout, modules/phoenix/data/zones/{temenos,apollyon}/mobs.yaml)
    ---------------------------------------------------------------------------
    { name = 'Proto-Ultima', zone = 'Temenos', group = 'Limbus', forced = true,
      pop = 'Central Temenos 4th Floor: KI Cosmo-Cleanse + White Card; Silver + Cerulean + Orchid Chip',
      src = 'scripts/battlefields/Temenos/central_temenos_4th_floor.lua:22' },
    { name = 'Proto-Omega', zone = 'Apollyon', group = 'Limbus', forced = true,
      pop = 'Central Apollyon: KI Cosmo-Cleanse + Red or Black Card; Smalt + Smoky + Charcoal + Magenta Chip',
      src = 'scripts/battlefields/Apollyon/central_apollyon.lua:23' },
}
