# Space Route Manager

Space Route Manager is a Factorio 2 0 mod for Space Age that lets you enable or disable individual routes on a space platform from a small in game panel

## Requirements

- Factorio 2 0
- Space Age

## Features

- Adds a route management button when a space platform hub GUI is opened
- Shows the current list of route destinations for the selected platform
- Lets you toggle each destination between active and disabled
- Applies the filtered route list back to the platform schedule
- Includes English and French locale files

## Installation

1. Copy the `space-route-manager_1.0.0` folder into your Factorio `mods` directory
2. Start Factorio with Space Age enabled
3. Enable the mod in the in game mod list if needed

## How To Use

1. Open a space platform hub
2. Click the Routes button added by the mod
3. Toggle the destinations you want to keep active or disable
4. Click Apply to update the platform schedule

## Notes

- The mod keeps a saved copy of the full route list in global state so the panel can continue to show all known destinations
- Route labels and interface text are localized through `locale/en/config.cfg` and `locale/fr/config.cfg`

## Project Files

- `control.lua` handles GUI events route toggling and schedule updates
- `data.lua` registers the custom sprite and GUI styles
- `locale/en/config.cfg` contains English text
- `locale/fr/config.cfg` contains French text
