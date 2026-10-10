extends RefCounted
class_name ShopStanding
## ShopStanding — Aetheria domain (how a keeper regards a customer, as four plain numbers).
##
## The value of ONE relationship dimension plus that dimension's configured bounds and neutral
## point. `ShopService` prices from this and nothing else, so pricing is testable with no
## relationship graph in the room; the runtime fills it from the real graph.

var value: int = 0
var neutral: int = 0
var minimum: int = 0
var maximum: int = 0


func _init(p_value: int = 0, p_neutral: int = 0, p_minimum: int = 0, p_maximum: int = 0) -> void:
	value = p_value
	neutral = p_neutral
	minimum = p_minimum
	maximum = p_maximum


## No opinion either way: what a customer with no edge to the keeper gets.
static func make_neutral() -> ShopStanding:
	return ShopStanding.new()
