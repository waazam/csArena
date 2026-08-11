class_name Weapons
## Static CS-flavored weapon definitions.
##  interval  seconds between shots        spread   half-cone in degrees
##  reach     preferred AI engage range    length   drawn barrel length (px)

const ORDER: Array[String] = ["glock", "usp", "mp5", "m4a4", "ak47", "nova", "awp"]

const DATA := {
	"glock": {
		name = "Glock-18", damage = 13, interval = 0.15, auto = false,
		speed = 1100.0, spread = 2.5, mag = 20, reserve = 100, reload = 1.0,
		pellets = 1, length = 12.0, recoil = 1.5, reach = 340.0,
		color = Color(0.72, 0.72, 0.78),
	},
	"usp": {
		name = "USP-S", damage = 20, interval = 0.18, auto = false,
		speed = 1150.0, spread = 1.8, mag = 12, reserve = 72, reload = 1.1,
		pellets = 1, length = 15.0, recoil = 2.0, reach = 380.0,
		color = Color(0.66, 0.68, 0.76),
	},
	"mp5": {
		name = "MP5-SD", damage = 12, interval = 0.075, auto = true,
		speed = 1000.0, spread = 3.5, mag = 30, reserve = 150, reload = 1.4,
		pellets = 1, length = 18.0, recoil = 1.2, reach = 300.0,
		color = Color(0.52, 0.55, 0.66),
	},
	"m4a4": {
		name = "M4A4", damage = 22, interval = 0.09, auto = true,
		speed = 1250.0, spread = 2.6, mag = 30, reserve = 120, reload = 1.6,
		pellets = 1, length = 24.0, recoil = 2.0, reach = 420.0,
		color = Color(0.45, 0.52, 0.46),
	},
	"ak47": {
		name = "AK-47", damage = 30, interval = 0.10, auto = true,
		speed = 1250.0, spread = 3.4, mag = 30, reserve = 120, reload = 1.7,
		pellets = 1, length = 24.0, recoil = 2.8, reach = 420.0,
		color = Color(0.58, 0.36, 0.20),
	},
	"nova": {
		name = "Nova", damage = 9, interval = 0.85, auto = false,
		speed = 950.0, spread = 9.0, mag = 8, reserve = 40, reload = 2.0,
		pellets = 8, length = 22.0, recoil = 5.0, reach = 200.0,
		color = Color(0.52, 0.26, 0.22),
	},
	"awp": {
		name = "AWP", damage = 110, interval = 1.4, auto = false,
		speed = 2000.0, spread = 0.4, mag = 5, reserve = 20, reload = 2.4,
		pellets = 1, length = 30.0, recoil = 8.0, reach = 700.0,
		color = Color(0.36, 0.52, 0.32),
	},
}
