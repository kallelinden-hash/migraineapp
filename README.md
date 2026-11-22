# Migrändagbok för iPhone och Apple Watch

Registrera start och slut på Apple Watch. Ett lyckat sparande bekräftas med en vibration. Anfallen sparas lokalt på klockan och förs över till iPhone när enheterna kan synka. På iPhone kan du justera starttiden och lägga till intensitet, aura, läkemedel och upplevd effekt. Månadsöversikten räknar kalenderdagar med registrerade anfall. Ett anfall som går över midnatt kan därför ge två migrändagar.

I anfallsdetaljerna kan du be appen läsa Apple Hälsa. Appen visar tillgänglig sömntid, puls och pulsvariation under de 24 timmarna före vald starttid. Den visar också sömntid under ett tidigare jämförbart dygn utan registrerat anfall, om ett sådant dygn finns inom 14 dagar. Mätvärden läses på begäran. Dagboken lagras lokalt utan eget konto eller server.

## Kör på egna enheter

1. Packa upp filen på en Mac. Öppna `Migrandagbok.xcodeproj` i Xcode.
2. Välj ditt team under **Signing & Capabilities** för båda målen. Om du behöver ändra apparnas identifierare ska klockans börja med iPhone-appens identifierare plus en punkt. Uppdatera då även `WKCompanionAppBundleIdentifier` för klockmålet så att det matchar iPhone-appens identifierare.
3. Kör schemat **Migrandagbok** på iPhone (iOS 17 eller senare). Installera klockappen på parkopplad Apple Watch (watchOS 10 eller senare). Om den inte installeras automatiskt, prova via Watch-appen på iPhone eller kör schemat **Migrandagbok Watch** på klockan. Signeringsteamet måste kunna använda HealthKit.
4. Öppna båda apparna. Tryck **Anfall startat** på klockan och kontrollera att ett pågående anfall dyker upp på mobilen. Tryck **Anfall slut** och kontrollera att längden visas.
5. Testa också ett helt anfall när klockan saknar kontakt med mobilen. Öppna båda apparna efter återanslutning och kontrollera att iPhone visar ett anfall med båda tiderna. Öppna anfallsdetaljerna, justera starttiden och välj **Hämta mätningar** för att testa Apple Hälsa med tillgängliga data.

Källkoden är framtagen i Linux. Byggning, signering, haptik, enhetssynk och HealthKit behöver verifieras i Xcode och på parkopplade enheter.
