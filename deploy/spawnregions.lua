-- Copied to <cachedir>/Server/<SERVER_NAME>_spawnregions.lua on every start.
-- Every Build 42 town is listed, so players can spawn in any of them; with
-- more than one region the spawn screen also offers "Random".
--
-- The towns added in Build 42 are listed under plain names on purpose: their
-- map.info says only_for_game_mode=Sandbox, and the spawn screen hides a
-- region whose name matches such a map folder unless the game mode is
-- Sandbox (multiplayer isn't). A name that isn't a map folder skips that
-- check; the spawn itself only uses the points loaded from `file`, so they
-- work the same, just without the map preview zoom and description.
function SpawnRegions()
	return {
		{ name = "Muldraugh, KY", file = "media/maps/Muldraugh, KY/spawnpoints.lua" },
		{ name = "Riverside, KY", file = "media/maps/Riverside, KY/spawnpoints.lua" },
		{ name = "Rosewood, KY", file = "media/maps/Rosewood, KY/spawnpoints.lua" },
		{ name = "West Point, KY", file = "media/maps/West Point, KY/spawnpoints.lua" },
		{ name = "Brandenburg", file = "media/maps/Brandenburg, KY/spawnpoints.lua" },
		{ name = "Echo Creek", file = "media/maps/Echo Creek, KY/spawnpoints.lua" },
		{ name = "Ekron", file = "media/maps/Ekron, KY/spawnpoints.lua" },
		{ name = "Fallas Lake", file = "media/maps/Fallas Lake, KY/spawnpoints.lua" },
		{ name = "Irvington", file = "media/maps/Irvington, KY/spawnpoints.lua" },
		{ name = "March Ridge", file = "media/maps/March Ridge, KY/spawnpoints.lua" },
		{ name = "Valley Station", file = "media/maps/Valley Station, KY/spawnpoints.lua" },
	}
end
