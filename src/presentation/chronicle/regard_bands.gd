extends RefCounted
class_name RegardBands
## RegardBands — Aetheria presentation (a relationship number said in a word, D-073 §4).
##
## The relationship graph holds a NUMBER on each independent dimension; a newcomer cannot read
## "-10" or "15". This says where a value stands on its own dimension's range, as one of five
## bands, and names the localization key for that band of that dimension. Presentation only:
## the graph is asked for the value and the range, nothing here is stored or written, and
## dimensions are NEVER added together (`RELATIONSHIP_SYSTEM.md`: they are independent — a sum
## would be the single good/evil score the design forbids).
##
## A dimension that can go below zero (affinity, debt) is read about its middle; one that
## cannot (trust, respect, fear, rivalry) is read up from nothing.

const BAND_LOWEST := 0
const BAND_LOW := 1
const BAND_MIDDLE := 2
const BAND_HIGH := 3
const BAND_HIGHEST := 4
const BAND_COUNT := 5

## Signed dimensions, as a fraction of the larger side of the range: where LOW ends below the
## middle, where the MIDDLE ends, where HIGHEST begins. One impression (±5…±20 of 100) leaves
## the middle; it takes a history to reach an end.
const SIGNED_EDGE := 0.04
const SIGNED_FAR := 0.40
## Unsigned dimensions, as a fraction of the maximum: 0 is LOWEST ("none"); then these.
const UNSIGNED_LOW := 0.20
const UNSIGNED_MIDDLE := 0.50
const UNSIGNED_HIGH := 0.80

const KEY_FORMAT := "UI_REL_BAND_%s_%d"


## The band `value` falls in on a dimension spanning `minimum`…`maximum`.
static func band(value: int, minimum: int, maximum: int) -> int:
	if maximum <= minimum:
		return BAND_MIDDLE
	if minimum < 0:
		var reach := float(maxi(absi(minimum), absi(maximum)))
		var signed := float(value) / reach
		if signed <= -SIGNED_FAR:
			return BAND_LOWEST
		if signed < -SIGNED_EDGE:
			return BAND_LOW
		if signed <= SIGNED_EDGE:
			return BAND_MIDDLE
		if signed < SIGNED_FAR:
			return BAND_HIGH
		return BAND_HIGHEST
	var part := float(value - minimum) / float(maximum - minimum)
	if value <= minimum:
		return BAND_LOWEST
	if part < UNSIGNED_LOW:
		return BAND_LOW
	if part < UNSIGNED_MIDDLE:
		return BAND_MIDDLE
	if part < UNSIGNED_HIGH:
		return BAND_HIGH
	return BAND_HIGHEST


## The localization key of the word for `dimension` at `value`.
static func key(dimension: StringName, value: int, minimum: int, maximum: int) -> String:
	return KEY_FORMAT % [String(dimension).to_upper(), band(value, minimum, maximum)]


## The key of a dimension's own name ("affinity", "trust").
static func name_key(dimension: StringName) -> String:
	return "UI_REL_DIM_%s" % String(dimension).to_upper()
