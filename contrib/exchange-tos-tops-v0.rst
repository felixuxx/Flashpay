
1.1. Dienstleistung / Geltungsbereich
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- **Nutzer** bezeichnet Inhaber von Taler-Wallets und damit Zahlende bzw. potenziell
Zahlende.

CG: "Kunden sind Inhaber von durch TOPS signierten und in CHF denominierten Wertmarken
welche in Taler-Wallets in Eigenverantwortung gespeichert werden und mit denen Kunden
bezahlen koennen."

[KOMMENTAR SK]
1. Ich empfehle weiterhin den Rechtsbegriff **Nutzer** anstelle von "Kunden", denn
Händler/Verkäufer können ja auch Nutzer sein, die untereinander Wertmarken austauschen,
ohne untereinander Kunden sein zu müssen. Sie sind damit "Nutzer" wie alle anderen Nutzer, die
wiederum keine Händler sein müssen. Das gilt selbstredend auch für P2P-Transaktionen von Wallets,
die keine Zahlung auslösen, sondern nur Token an andere Wallets übertragen wollen.
2. Nutzer sind **Eigentümer** von Wertmarken - denn "Inhaber" oder "Besitzer" wären hierfür
rechtlich schwache und unzutreffende Rechtsbegriffe. Wir sollten in diesem Punkt exakt sein,
wenn wir mit der Definition von e-Geld konform bleiben wollen (Wertmarken/Token, die in
Wallets bis zu ihrer Einlösung als Eigentum der Wallet-Eigentümer verwahrt werden).

Daher nun folgender **Formulierungsvorschlag**:
- **Nutzer** sind Eigentümer von durch TOPS signierten und in CHF denominierten Wertmarken, welche
sie in Taler-Wallets in Eigenverantwortung als ihr Eigentum speichern und mit denen sie bezahlen
können. Ist eine Wertmarke eingelöst worden, kann diese nicht noch ein weiteres Mal eingelöst werden.
Wer eine Wertmarke zuerst einlöst, hat ihren Wert zur Zahlung verwendet.
Die Nutzer anerkennen sämtliche getätigten Zahlungen aus dem Taler-Wallet, selbst wenn diese ohne
ihre Zustimmung erfolgt sind.
[KOMMENTAR SK]

1.2. Zugang zu den TALER Dienstleistungen
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

TALER ist ein System, das bargeldlose Zahlungen über den TALER-Zahlungsdienst ermöglicht.
TALER kann von Nutzern verwendet werden, um Zahlungen zwischen TALER-Nutzern durchzuführen und als
Zahlungsmittel im stationären Handel, an Automaten, online und in Apps bei autorisierten Händlern
oder Dienstleistungsanbietern, die TALER als Zahlungsmittel akzeptieren (nachfolgend
"**Begünstigte**"), eingesetzt zu werden.

[KOMMENTAR SK]
1.2. **Zugang zum TALER-Zahlungsdienst und zu anderen TOPS-Dienstleistungen**.
[KOMMENTAR SK]

1.4. Registrierung und Identifizierung
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Zur Nutzung von TALER sind die Kundinnen und Kunden verpflichtet, sich in bei TALER zu
registrieren und die verlangten Informationen zur Verfügung zu stellen. Die TALER AG behält
sich vor, zur Erfüllung regulatorischer Vorgaben jederzeit weitere Informationen zu
verlangen. Die registrierte Telefonnummer wird aus Sicherheitsgründen per SMS verifiziert.
Mit der Registration bestätigt die Kundin bzw. der Kunde, die rechtmässige Nutzerin bzw.
Nutzer der Telefonnummer und des Smartphones zu sein.
Bei einer Änderung der bei der Registrierung angegebenen Daten müssen diese unverzüglich in
TALER aktualisiert werden.
Die TALER AG behält sich vor, Registrierungsgesuche ohne Angabe von Gründen abzulehnen bzw.
bereits erfolgte Registrationen wieder rückgängig zu machen.

CG: Bitte allgemeiner halten, die Grenzwerte CHF sollten gar nicht explizit in
den AGBs auftauchen!  Stattdessen: "Zur Nutzung des Zahlungsdienstes sind
Kunden und Beguenstigte verpflichtet TOPS bei der Erfuellung regulatorischer
Vorgaben zu unterstuetzen. Insbesondere kann TOPS Auskunft verlangen ueber die
Identitaet von wirtschaftlich Beguenstigten.  TOPS hat das Recht und die
Pflicht ggf. Kunden und Beguenstigte von der Nutzung des Systems
auszuschliessen sollten diese die notwendigen Auskuenfte verweigern oder
inkorrekte Angaben machen."

[KOMMENTAR SK]
Meine Vorschläge dazu:
1.4.1. Zur Nutzung des Zahlungsdiensts sind Nutzer und Begünstigte verpflichtet, TOPS bei
der Erfüllung regulatorischer und gesetzlicher Vorgaben zu unterstützen. Insbesondere kann
TOPS über die Identität von **wirtschaftlich Berechtigten** Auskunft verlangen. TOPS hat
das Recht und ggf. die gesetzliche Pflicht, Nutzer und Begünstigte von der Nutzung des
Zahlungsdiensts auszuschliessen, sollten diese die erforderlichen Auskünfte verweigern oder unwahre
Angaben machen.

1.4.2. Zur Nutzung des Zahlungsdiensts gehen **Begünstigte** eine Geschäftsbeziehung mit
TOPS ein und können ggf. verpflichtet sein, sich bei TOPS zu registrieren und die dabei
verlangten Informationen zur Verfügung zu stellen. TOPS benötigt zur Registrierung von
Begünstigten deren IBAN, Adresse und Telefonnummer. TOPS behält sich vor, zur Erfüllung
regulatorischer Vorgaben jederzeit weitere Informationen verlangen zu können.

1.4.3. Es erfolgt keine Registrierung oder Kontenanlage der **Nutzer** bei TOPS oder dem
Taler-Zahlungsdienst. Erfasst werden jedoch IBAN-Konten, die CHF an TOPS überweisen.
Die Nutzer brauchen für das Abheben in Taler-Wallets eine Schweizer Telefonnummer zum
Empfang von TANs im Fall der TAN-Versendung durch den Taler-Zahlungsdienst.
[KOMMENTAR SK]

1.10. Kommunikation
~~~~~~~~~~~~~~~~~~~

CG: Die Kommunikation von TOPS zu Nutzern erfolgt grundsätzlich
über Benachrichtigungen im GNU Taler Protokoll. Nutzer sind dafuer verantwortlich auf
entsprechende Benachrichtigungen zu reagieren. TOPS hat das Recht, Transaktionen
nicht auszufuehren bis Nutzer auf diesem Weg angeforderte rechtlich notwendige Daten
bereitstellen.

[KOMMENTAR SK]
Nachfolgender Text wird einfach nur von oben übernommen und orthografisch berichtigt und das GNU
ausgelassen:

Die Kommunikation von TOPS zu Nutzern erfolgt grundsätzlich über Benachrichtigungen im
Taler-Protokoll. Die Nutzer sind dafür verantwortlich, auf entsprechende Benachrichtigungen zu
reagieren. TOPS hat das Recht, Transaktionen solange nicht auszuführen, bis Nutzer auf diesem Weg
angeforderte rechtlich notwendige Daten bereitstellen.
[KOMMENTAR SK]

1.12. Vorbehalt gesetzlicher Regelungen und Beschränkung der Dienstleistungen
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Allfällige Gesetzesbestimmungen, die den Betrieb und die Benutzung von Smartphones,
Zahlungssystemen, des Internets und sonstiger dedizierter Infrastruktur regeln, bleiben
vorbehalten und gelten ab ihrer Inkraftsetzung auch für die vorliegenden Dienstleistungen.
Die Benutzung der Dienstleistungen aus dem Ausland kann lokalen rechtlichen Restriktionen
unterliegen oder unter Umständen Regeln des ausländischen Rechts verletzen. Die
Zahlungsfunktion ist grundsätzlich auf das Hoheitsgebiet der Schweiz beschränkt und darf im
Ausland nicht in Anspruch genommen werden.

Die TALER AG behält sich vor, das Angebot von TALER jederzeit und ohne vorherige Ankündigung
zu ändern, zu beschränken oder vollständig einzustellen, insbesondere aufgrund rechtlicher
Anforderungen, technischen Problemen, zwecks Verhinderung von Missbräuchen, auf behördliche
Anordnung oder aus Sicherheitsgründen.
Die TALER AG kann nach eigenem Ermessen und ohne vorherige Ankündigung die Nutzung von TALER
für einzelne Kundinnen und Kunden einschränken oder unterbinden, Zahlungen nicht oder nur
verzögert verarbeiten, eingehende Zahlungen zurückweisen und das Auf- und Entladen
beschränken, insbesondere wo dies nach Auffassung der TALER AG aus rechtlichen Gründen oder
solchen, die die Reputation betreffen, angezeigt ist, bei IT-gestützten Angriffen, bei
Missbrauch oder bei Betrugsverdacht. Im Verlaufe der Dauer der Geschäftsbeziehung können
Umstände eintreten, die die TALER AG verpflichten, Vermögenswerte zu sperren, die
Geschäftsbeziehung einer zuständigen Behörde zu melden oder abzubrechen.
Die Kundinnen und Kunden sind verpflichtet, der TALER AG auf Verlangen Auskünfte zu
erteilen, die die TALER AG benötigt, um den gesetzlichen oder internen Abklärungs- oder
Meldepflichten nachzukommen.

CG: scheint mir vieles vorher gesagtes zu duplizieren. Ggf. oben Text streichen?

[KOMMENTAR SK]
Mein auf das Wesentliche reduzierter Vorschlag, um stets im Rahmen der (unvorhersehbaren)
Entwicklung der Regulatorik zu bleiben:

1.12.1 Allfällige Gesetzesbestimmungen, die den Betrieb und die Nutzung von digitalen Endgeräten,
Zahlungsdiensten, des Internets und sonstiger Infrastruktur regeln, bleiben vorbehalten und gelten
ab ihrer Inkraftsetzung auch für die TOPS-Dienstleistungen.

1.12.2 TOPS behält sich vor, das Angebot von Dienstleistungen jederzeit und ohne vorherige
Ankündigung zu ändern, zu beschränken oder vollständig einzustellen, insbesondere aufgrund
rechtlicher Anforderungen, technischen Problemen, zwecks Verhinderung von Missbräuchen, auf
behördliche Anordnung oder aus Sicherheitsgründen.
[KOMMENTAR SK]

1.14 Datenschutz
~~~~~~~~~~~~~~~~

Weitere Informationen zu den Datenbearbeitungen finden sich in der Datenschutzerklärung auf
der Webseite der TALER AG (www.TALER.ch).

[KOMMENTAR SK]
TALER AG (www.TALER.ch) --> TOPS (www.taler-ops.ch)
[KOMMENTAR SK]

1.15. Dauer und Kündigung
~~~~~~~~~~~~~~~~~~~~~~~~~

Die Geschäftsbeziehung zwischen der Kundin bzw. dem Kunden und der TALER AG wird für
unbestimmte Dauer abgeschlossen.
Die Kundinnen und Kunden können ihr TALER Guthaben auf TALER jederzeit saldieren und
schliessen, was als Kündigung gilt. Die TALER AG kann ihrerseits die Geschäftsbeziehung
jederzeit mit sofortiger Wirkung kündigen.

Erfolgt während 4 Jahren keine Transaktion, gilt die Geschäftsbeziehung als durch die Kundin
bzw. den Kunden gekündigt.

SK alt:
- Satz 1: Die Geschäftsbeziehung zwischen den Begünstigten (Händler, Betriebe, Verkäufer
und sonstige Empfänger von Überweisungen des Zahlungsdienst an die begünstigten
IBAN-Konten) und dem Zahlungsdienstleister wird auf eine unbestimmte Dauer abgeschlossen.

CG: Ja.

- Satz 2: Die Nutzer von Taler-Wallets können das Guthaben jederzeit an die Bankkonten
zurücküberweisen lassen, von denen die Überweisung der Nutzer an den Zahlungsdienst
erfolgte, und so das Guthaben auf Null setzen.

CG: Auch OK, wobei "saldieren" ggf. besser ist.

- Satz 3: Die TALER AG kann die Geschäftsbeziehung mit den Begünstigten jederzeit -
insbesondere in Missbrauchsfällen mit sofortiger Wirkung - kündigen.
- Satz 4: Eine schriftliche Kündigung der TALER AG erfolgt an eine der zuletzt
bekanntgegebenen Adressen der Geschäftspartner (z.B. per E-Mail oder Brief).
- Satz 5: Streichen

CG: Ja, wir brauchen ggf. noch etwas das TOPS bei Betriebsaufgabe die Nutzer ueber
   das Taler-Protokoll informiert und die Wallets in diesem Fall die Kunden
   auffordern werden, bestehende Restguthaben zu saldieren. Kunden die dies
   unterlassen, verlieren dann nach 3 Monaten den Anspruch auf das Restguthaben.

[KOMMENTAR SK]
Mein Vorschlag:
1.15 Dauer und Kündigung der Geschäftsbeziehung

1.15.1 Die Geschäftsbeziehung zwischen TOPS und **Begünstigten** (Händler, Betriebe, Verkäufer und sonstige
Empfänger von Überweisungen des Zahlungsdiensts an die begünstigten IBAN-Konten) wird auf eine unbestimmte Dauer
abgeschlossen. TOPS kann die Geschäftsbeziehung mit den Begünstigten jederzeit - insbesondere in Missbrauchsfällen mit
sofortiger Wirkung - kündigen. Eine schriftliche Kündigung durch TOPS erfolgt an eine der zuletzt bekanntgegebenen
Adressen der Geschäftspartner (z.B. per E-Mail oder Brief). Sollten für über 12 Monate keine Transaktionen an die
Begünstigen erfolgen, gilt die Geschäftsbeziehung als beendet.

1.15.2 Die Geschäftsbeziehung zwischen TOPS und **Nutzern** wird auf die Dauer der Nutzung des Zahlungsdiensts
abgeschlossen. Die Nutzer von Taler-Wallets können das Guthaben in diesen jederzeit an die Bankkonten zurücküberweisen
lassen, von denen die Überweisung der Nutzer an den Zahlungsdienst erfolgte, und so das Guthaben saldieren. Bei einer
Betriebsaufgabe des Zahlungsdiensts der TOPS werden die Nutzer über die bevorstehende Einstellung des Zahlungsdiensts
durch das Taler-Protokoll informiert und von den Taler-Wallets aufgefordert, das bestehende Guthaben zu saldieren.
Nutzer, die diese Saldierung unterlassen, verlieren nach 3 Monaten den Anspruch auf das danach noch bestehende
Guthaben, welches in das Eigentum der TOPS übergeht.
[KOMMENTAR SK]

1.17. Anwendbares Recht und Gerichtsstand
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Soweit gesetzlich zulässig, unterstehen alle Rechtsbeziehungen zwischen den Kundinnen und
Kunden und der TALER AG (inkl. internationalen Zahlungen) ausschliesslich dem materiellen
schweizerischen Recht, unter Ausschluss von Kollisionsrecht und unter Ausschluss von
Staatsverträgen.
Unter dem Vorbehalt von entgegenstehenden, zwingenden gesetzlichen Bestimmungen ist Zürich
ausschliesslicher Gerichtsstand und Erfüllungsort. Für Kundinnen und Kunden mit Wohnsitz
ausserhalb der Schweiz ist Zürich sodann auch Betreibungsort.

- Satz 2: Zürich --> Biel

CG: TOPS: Ich denke Bern, nicht Biel (so was ist doch bestimmt Kantonal!?)

[KOMMENTAR SK]
Subkantonal. Das Regionalgericht in Biel ist zuständig als erstinstanzliche Zivilrechtsabteilung und als
Schlichtungsbehörde (siehe https://www.zsg.justice.be.ch/de/start/ueber-uns/regionalgerichte/berner-jura-seeland.html):
Regionalgericht Berner Jura-Seeland, Amthaus Biel, Spitalstrasse 14, 2502 Biel.

Hinsichtlich NetzBon gilt der Gerichtsstand, der im Vertrag zwischen Taler Operations AG und dem Verein Soziale
Ökonomie vereinbart wird.
[KOMMENTAR SK]

[NETZBON-NEU]
Bei etwaigen Streitigkeiten oder Unstimmigkeiten, die aus der Nutzung von Taler, der
Taler-App und eNetzBon entstehen, verpflichten sich die Parteien, zunächst eine gütliche
Einigung anzustreben. Wenn keine Einigung erzielt werden kann, unterliegt die
Streitbeilegung den geltenden schweizerischen Gesetzen und der Gerichtsbarkeit von Biel.
[NETZBON-NEU]

CG: Netzbon is Biel!? Nicht Basel?
