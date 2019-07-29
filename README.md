# blap-2019-years-plugin
Plugin for blap "Legacy TF2" segment. A far from exhaustive but reasonable representation of past years of TF2.

## Features
* Change years at any time
* Modifies player items to remove features that didn't exist in the current year, including:
    * Item qualities in years before they were introduced
    * Strange parts
    * Killstreaks
    * Australiums
    * The item itself if it didn't exist, replacing with stock
* Enabling/disabling of past bugs/features, including:
    * Dropped weapons
    * Unlimited airducks
    * Taunt sliding
    * Pre round damage push
    * Disabling spec and spawn xray
    * Building pickup
    * EOTL ducks
    * Pre jungle inferno airblast, or no air blast at all

## Requirements

* TFTrue - Whitelist changing
* TF2Items - Item replacement
* TF2Attributes - Attribute checking
* Buildings extension - Small extension to hook building pickups

## Cvars
 * `sm_current_year` - The current year
 
## Commands
 * `sm_year` - Sets the current year

## License

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License. To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-sa/4.0/ or send a letter to Creative Commons, PO Box 1866, Mountain View, CA 94042, USA.
