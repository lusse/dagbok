# Dagbok

Ett World of Warcraft-addon som för dagbok över din karaktär, och en hemsida som berättar historien.

**Läs krönikan:** https://lusse.github.io/dagbok/

## Addonet

Dagboken skriver automatiskt ner det som är värt att minnas och tar skärmdumpar vid de stora ögonblicken:

- nivåer (bild var 10:e nivå), bossar, sällsynta monster och bedrifter
- loot (blått och bättre loggas, episkt och bättre fotograferas) och värdet på allt du plockat upp
- nya zoner, dungeons och slagfält, uppdrag, guld, guild, rykte, yrken och första riddjuret
- dödsfall, PvP-kills, PvP-dödsfall, dueller, favoritoffer och ärkefiender
- följeslagare: vilka du grupperar med, hur länge och hur många bossar ni fällt tillsammans

Installera genom att kopiera mappen `Dagbok` till `World of Warcraft\_<version>_\Interface\AddOns\`.

| Kommando | |
|---|---|
| `/dagbok` | öppna eller stäng dagboken |
| `/dagbok minne <text>` | skriv ett eget minne (med skärmdump) |
| `/dagbok niva N` | skärmdump var N:e nivå |
| `/dagbok kvalitet N` | skärmdump för loot från kvalitet N |
| `/dagbok pvp N` | skärmdump var N:e PvP-kill |
| `/dagbok hjalp` | visa alla kommandon |

## Hemsidan

`Hemsida/Uppdatera hemsidan.cmd` läser dagboken från WoW:s SavedVariables, kopierar in skärmdumparna och öppnar sidan lokalt.
`Hemsida/Publicera hemsidan.cmd` gör samma sak och lägger sedan upp den nya versionen här på GitHub.

WoW sparar dagboken först när du loggar ut eller kör `/reload`.
