<!-- private: docs/dev, never public. Entwurf LinkedIn-Artikel, Udo überarbeitet -->
# Konvergiert heißt nicht zulässig: PV/PQ-Umschaltung im Newton-Raphson-Lastfluss

Kurzfassung 2026-10-22. Zahlen aus der Studie `Welthulk/pvpq-study`, Stand
4ddd6bd, Sparlectra 0.60.0 vom GitHub-Commit a3cd5bc9. Abbildungen aus
`results/` der Studie.

---

Ein Lastfluss mit Q-Grenzen gilt als Routine: Ein Generator erreicht seine
Grenze, der Knoten wechselt von PV nach PQ, die Iteration läuft weiter.
Zeitpunkt und Reihenfolge der Umschaltung bestimmen aber mit, auf welcher
Lösung das Verfahren endet (Zeng et al., IJEPES 2023; Sundaresh und Rao,
Sadhana 2015).

Die Studie rechnet das mit Sparlectra.jl 0.60.0 nach und prüft jede
konvergierte Lösung, ob sie ein zulässiger Betriebspunkt ist. Skript, Daten
und Abbildungen liegen offen, ein zweiter Lauf liefert dieselben Dateien.

## Versuchsaufbau

Drei Umschaltstrategien von Sparlectra:

- `active_set`: Q-Grenzen als aktive Nebenbedingungen, ein Knoten an der
  Grenze wird über seine Spannung wieder nach PV freigegeben (Logik nach
  Zhao et al.)
- `classic_simultaneous`: alle verletzten Knoten gleichzeitig nach PQ
- `classic_one_at_a_time`: je Durchlauf ein Knoten

Die klassischen Strategien schalten wie MATPOWER nur von PV nach PQ.

![Abbildung 1: Ablauf der drei Strategien und die Zulässigkeitsprüfung](results/fig0_strategies.png)

Gleich für alle Läufe: Newton-Raphson in rechtwinkligen Koordinaten,
Toleranz 1e-6 pu, höchstens 80 Iterationen je Newton-Lösung, Start aus den Spannungen der
Falldatei, alle Hilfsverfahren aus, Stufensteller und SVC fest.

Testnetze: der 14-Knoten-Fall von Zeng et al. (case14_zeng), sp_case14 und
sp_case118 aus Sparlectra, und sp_case60_narrow: sp_case60 mit zwei
40-MW-Maschinen (Birkkamp_110, Westtal_110), deren Q-Band von -35 bis 35 auf
4,0 bis 5,5 Mvar verengt ist.

Zulässigkeit nach Zhao, Chiang, Li, Ju (PSCC 2008): Ein Generator hält
seinen Sollwert mit Q im Band, oder er steht an einer Grenze. An Qmax muss
U <= U_set sein, an Qmin U >= U_set. Eine Maschine an Qmax mit U über dem
Sollwert würde die Erregung zurücknehmen; das Paper nennt solche Lösungen
anormal. Toleranzen 1e-6 pu und 0,001 Mvar.

## Ergebnis 1: ein Netz, drei Lösungen, eine davon zulässig

case14_zeng, alle drei Strategien konvergieren auf 1e-6 pu:

| Strategie | Iterationen | Knoten PV nach PQ | Slack Q in Mvar | Verluste in MW | zulässig |
|---|---|---|---|---|---|
| active_set | 7 | 3 | 22,47 | 21,945 | ja |
| classic_simultaneous | 9 | 4 | 18,42 | 21,506 | nein, 3 Knoten |
| classic_one_at_a_time | 11 | 2 | 22,26 | 21,939 | nein, 1 Knoten |

![Abbildung 2: Spannungsprofil der drei Lösungen, case14_zeng](results/fig5a_voltage_profile.png)

Die Spannungen liegen bis 0,0118 pu auseinander. `classic_simultaneous`
endet auf der anormalen Lösung: Knoten 2, 3 und 6 stehen an Qmax, die
Spannung liegt 0,008 bis 0,012 pu über dem Sollwert. Ein Rückweg nach PV
würde sie freigeben, die klassische Strategie hat keinen.
`classic_one_at_a_time` lässt Knoten 6 als PV mit 24,68 Mvar bei einer
Grenze von 24 Mvar stehen.

Zusätzlich wurde an jedem Knoten an einer Grenze geprüft, ob mehr
Blindleistung die Spannung dort anhebt (dU/dQ > 0, das Stabilitätskriterium
bei Zhao et al.). Das ist überall der Fall, auch an den drei anormalen
Knoten. Dieser Test allein hätte die anormale Lösung also nicht erkannt;
erst der Vergleich von Spannung und Sollwert zeigt sie.

## Ergebnis 2: gleiche Lösung, unterschiedlicher Aufwand

In sp_case118 wechseln 10 Knoten nach PQ. Alle drei Strategien enden auf
derselben zulässigen Lösung: `active_set` nach 5 Iterationen,
`classic_simultaneous` nach 8, `classic_one_at_a_time` nach 35. In
sp_case14 erreicht keine Maschine ihre Grenze.

## Ergebnis 3: Maschinen mit schmalem Q-Band

In sp_case60_narrow bräuchten Birkkamp_110 und Westtal_110 am Sollwert 7,26
und 5,71 Mvar, das Band endet bei 5,5 Mvar. Alle drei Strategien
konvergieren in 4 Iterationen.

| Strategie | Birkkamp_110 | Westtal_110 | zulässig |
|---|---|---|---|
| active_set | 0,9966 pu, 5,50 Mvar (Qmax) | 0,9883 pu, 5,50 Mvar (Qmax) | ja |
| beide classic | 1,0031 pu, 5,50 Mvar (Qmax) | 1,0200 pu, 6,14 Mvar (PV) | nein, Q über Qmax |

Die 0,64 Mvar über Qmax kommen aus der Q-Hysterese der klassischen
Strategien: bis 0,01 pu (1 Mvar bei 100 MVA) bleibt der Knoten PV. Bei einem
Band von 1,5 Mvar sind das zwei Drittel des Bandes. Mit Hysterese 0 enden
beide klassischen Strategien hier und `classic_one_at_a_time` in case14_zeng
auf der Lösung von `active_set`. `classic_simultaneous` in case14_zeng
bleibt auch dann anormal: Dort fehlt der Rückweg nach PV, nicht eine
kleinere Toleranz.

Am zulässigen Punkt ist der kleinste Eigenwert der reduzierten Jacobi-Matrix
0,007, die Lösung liegt nahe der Spannungsstabilitätsgrenze. Wird
Birkkamp_110 von Hand als PQ gesetzt, konvergiert der Lauf (7 Iterationen),
die Maschine steht dann aber an Qmin mit 0,9855 pu unter dem Sollwert.
Westtal_110 allein oder beide zusammen als PQ: keine Konvergenz.

## Ergebnis 4: Kennlinien statt Umschaltung

Zwei Kennlinien ersetzen den Spannungsregler. Die Maschine wird PQ-Knoten,
Q folgt U, es gibt nichts umzuschalten:

- Q(U)-Statik: linear von (U_set - dU, Qmax) bis (U_set + dU, Qmin), dU 0,5
  bis 5 % von U_set.
- Soft-PV nach Kataoka (ISCAS 2005), linear angenähert: U_set wird auf 0,1 %
  gehalten, solange Q in den mittleren 80 % des Bandes liegt; die letzten
  10 % je Seite laufen über dU_c (1, 2 oder 5 %) aus.

case14_zeng, Kennlinie an allen vier PV-Maschinen, Start am Sollwert:

- Alle drei Strategien enden auf derselben Lösung, weil nichts mehr
  umzuschalten ist.
- Statik: je steiler, desto näher an der zulässigen Lösung von
  `active_set`: 0,0050 pu bei dU 0,5 % mit denselben Zuständen, 0,0336 pu
  bei 5 %. Die beiden nicht zulässigen Lösungen liegen bei jeder Steilheit
  weiter weg.
- Soft-PV: 0,0076 pu (dU_c 1 %) und 0,0122 pu (dU_c 2 %) neben
  `active_set`, weiter weg als die Statik mit 0,5 %. Keine Maschine bleibt
  im Mittelteil: Knoten 2 braucht 48,84 von 50 Mvar, also die obere Ecke.
  Mit dU_c 5 % landen alle Strategien auf 0,59 bis 0,72 pu, alle vier
  Maschinen an Qmax.

![Abbildung 3: Abstand der Q(U)-Statik zu den drei umgeschalteten Lösungen über dU, case14_zeng](results/fig6_zeng_softpv.png)

sp_case60_narrow: Statik 0,5 und 1 % und Soft-PV mit dU_c 1 % treffen die
Lösung von `active_set` (unter 1e-6 pu), Soft-PV mit dU_c 2 % liegt 0,0008 pu
daneben. Die klassische Lösung mit 6,14 Mvar liegt über Qmax und damit auf
keiner Kennlinie.

![Abbildung 4: sp_case60_narrow, Q über U an beiden Maschinen, links Q(U)-Statik dU 1 %, rechts Soft-PV dU_c 2 %, mit den drei umgeschalteten Lösungen](results/fig8_kataoka.png)

sp_case118, Kennlinie an allen 53 PV-Maschinen: ungedämpft konvergiert keine
Strategie. Gedämpft liegt Soft-PV (dU_c 2 %) nach 6 Iterationen 0,0019 pu neben
`active_set`, die Statik 0,5 % nach 49 Iterationen 0,0030 pu.

Startwert: Starten die vier Maschinen in case14_zeng auf 1,0 pu statt am
Sollwert, endet die Statik bei jeder Steilheit auf 0,59 bis 0,72 pu (dU 1
und 2 % nur gedämpft), alle vier an Qmax, 51,8 MW Verluste statt 22,1 bis 22,9. Die Bedingungen von
Zhao et al. sind erfüllt, aber dU/dQ ist an drei Knoten negativ und der
kleinste Eigenwert -0,62: eine spannungsinstabile Lösung. Konvergiert heißt
auch bei Kennlinien nicht stabil.

Bleiben PV-Maschinen übrig (Statik nur an Knoten 2 und 6), entscheidet die
Strategie wieder: `active_set` endet bei dU 0,5 % auf der Lösung mit 22,14
MW Verlusten, `classic_simultaneous` nur gedämpft bei 0,85 und 0,89 pu mit
32,52 MW und Eigenwert -0,13.

## Sollwert gegen gelöste Spannung

Je Maschine Sollwert, gelöste Spannung, Q und Endzustand (vollständig in der
Studie, `consistency.csv` und `consistency_softpv.csv`). Die nicht plausiblen
Maschinen:

| Lauf | Maschine | U_set | U | Q in Mvar | Qmax | Endzustand | Befund |
|---|---|---|---|---|---|---|---|
| case14_zeng, classic_simultaneous | 2 | 1,045 | 1,0568 | 50,00 | 50 | Qmax | U über U_set |
| case14_zeng, classic_simultaneous | 3 | 1,01 | 1,0179 | 40,00 | 40 | Qmax | U über U_set |
| case14_zeng, classic_simultaneous | 6 | 1,07 | 1,0790 | 24,00 | 24 | Qmax | U über U_set |
| case14_zeng, classic_one_at_a_time | 6 | 1,07 | 1,0700 | 24,68 | 24 | PV | Q über Qmax |
| sp_case60_narrow, beide classic | Westtal_110 | 1,02 | 1,0200 | 6,14 | 5,5 | PV | Q über Qmax |
| sp_case60_narrow, Birkkamp_110 von Hand PQ | Birkkamp_110 | 1,01 | 0,9855 | 4,00 | 5,5 | Qmin | U unter U_set |
| case14_zeng, Statik an 2 und 6, gedämpft, 32,52 MW | 1 | 1,06 | 0,8792 | 0,00 | 50 | Qmin | U unter U_set, dU/dQ negativ |
| case14_zeng, Statik an 2 und 6, gedämpft, 32,52 MW | 3 | 1,01 | 0,8072 | 40,00 | 40 | Qmax | dU/dQ negativ |

Zwei Fehlerbilder: U über U_set an Qmax (fehlender Rückweg nach PV) und Q
über Qmax am Sollwert (Hysterese). Die letzten drei Zeilen gehören zu
Lösungen, die schon in Ergebnis 3 und 4 ausscheiden: Birkkamp_110 von Hand
als PQ und die spannungsinstabile Lösung mit Statik an Knoten 2 und 6.
Ebenso scheidet die Lösung mit 0,59 bis 0,72 pu aus Ergebnis 4 aus, dort ist
dU/dQ an den Kennlinien-Maschinen 1, 2 und 3 negativ. Alle übrigen
Maschinen in den vier Netzen sind plausibel, in sp_case118 alle 53 bei jeder
Strategie. Die Kennlinien-Maschinen erfüllen auf ihrer Kurve immer die
Bedingungen von Zhao et al., halten aber den Sollwert nicht: mit Soft-PV in
case14_zeng bis 0,0159 pu darunter, obwohl Q noch unter Qmax liegt.

## Grenzen der Studie

Die Befunde gelten für vier Netze und eine Programmversion. Geprüft wurde
jeweils die konvergierte Lösung; eine Stabilitätsanalyse mit Continuation
Power Flow, wie Zhao et al. sie als Gegenprobe nutzen, ersetzt das nicht.

## Fazit

Konvergiert heißt nicht zulässig. In case14_zeng und sp_case60_narrow enden
die klassischen Strategien auf Punkten, die die Maschinen so nicht fahren
würden. Hysterese 0 behebt nur den Fall Q über Qmax, nicht den fehlenden
Rückweg nach PV. `active_set` endet in allen vier Netzen zulässig.

Eine Kennlinie an allen PV-Maschinen macht das Ergebnis unabhängig von der
Strategie. Die Lösung hängt dann von Steilheit und Startwert ab und kann
spannungsinstabil sein.

Wer zwei Lastflussprogramme vergleicht, gibt Umschaltstrategie und
Q-Hysterese mit an und prüft jede Maschine an einer Q-Grenze gegen ihren
Sollwert.

Skript, Daten und Abbildungen: https://github.com/Welthulk/pvpq-study

Quellen:
- Schmitz, Udo: Sparlectra.jl: A Power-Flow and State-Estimation Framework
  in Julia, 2026, Version 0.60.0 (Commit a3cd5bc9).
  https://github.com/Welthulk/Sparlectra.jl
- Zhao, Chiang, Li, Ju: On PV-PQ Bus Type Switching Logic in Power Flow
  Computation. PSCC 2008.
- Zeng, Chiang, Neves, Alberto: On the accuracy of power flow and load margin
  calculation caused by incorrect logical PV/PQ switching: Analytics and
  improved methods. IJEPES 147 (2023) 108905.
- Sundaresh, Nagendra Rao: Investigation of schemes for incorporating
  generator Q limits in the fast decoupled load flow method. Sadhana 40(4)
  (2015) 1155-1168.
- Kataoka: A smooth power flow model of electric power system with generator
  reactive power limits taken into consideration. ISCAS 2005.

Wie geht ihr mit mehreren Lösungen im Lastfluss um?

#PowerSystems #JuliaLang #Lastfluss

