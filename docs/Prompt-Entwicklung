# Prompt-Entwicklung – Hintergrund zu HOW_TO_COPILOT.md

Dieses Dokument hält die methodischen Erkenntnisse fest, die in den
Auswertungs-Prompt aus `HOW_TO_COPILOT.md` eingeflossen sind. Es ist
keine Anwender-Anleitung – die steht in `HOW_TO_COPILOT.md` selbst –
sondern ein Werkstattbericht für die Weiterentwicklung.

Zweck: Wer in einem halben Jahr eine neue Fehlerklasse beobachtet und
den Prompt anpassen will, soll hier nachlesen können, *warum* der
Prompt so aussieht, wie er aussieht – und welche Versuchungen sich beim
Nachschärfen schon einmal als Sackgasse erwiesen haben.

---

## Die zentrale Erkenntnis

**Reihenfolge schlägt Regeln.**

Der Wendepunkt der Prompt-Entwicklung war nicht das Hinzufügen weiterer
Regeln, sondern das Erzwingen einer Reihenfolge: erst rechnen, dann
bewerten. Eine standortweise Aggregat-Tabelle als verpflichtender erster
Schritt – vor jeder Interpretation – hat mehr bewirkt als alle
Pflichtregeln zusammen.

Mustererkennende Systeme greifen sich gerne ein Einzelsignal mit
erzählerischem Potenzial (`ClientsCnt = 0` ist ein klassischer Fall) und
bauen darum eine kohärente, plausibel klingende Geschichte. Wenn das
Aggregat *vor* der Interpretation steht, wird das System in den
Buchhaltungs-Modus gezwungen. Erst Zahlen, dann Bedeutung.

Diese Erkenntnis wirkt über Copilot hinaus und sollte bei jeder
zukünftigen Anpassung der erste Reflex sein: *Lässt sich das Problem
durch eine Reihenfolge-Vorgabe lösen, bevor ich eine neue Regel ergänze?*

---

## Was ein guter Prompt für Copilot Basic leistet

In der Reihenfolge ihrer Wirksamkeit:

1. **Reihenfolge erzwingen.** Aggregat-Tabelle vor Interpretation.
   Strukturvorgaben werden zuverlässig befolgt, einzelne
   Schwellenwert-Regeln nicht.
2. **Domänenwissen mitliefern.** Felder wie `CachePr`, `ClientsCnt`,
   `applePendingVersion` sind nicht selbsterklärend. Ohne erklärendes
   Datenmodell rät Copilot. Pro Spalte: Bedeutung, Wertetyp,
   Interpretationsrichtung, Caveat.
3. **Tonangabe.** Hypothesen statt Urteile, Befund nur bei mehreren
   konsistenten Signalen, Unsicherheiten benennen statt glätten, keine
   Schuldzuweisungen. Das ist kein Schmuck, sondern verhindert
   vorschnelle Kategorisierung.
4. **Gegenanweisungen für beobachtete Fehlinterpretationen.** Jede in
   der Praxis aufgetretene Fehlinterpretation wird im Datenmodell
   explizit adressiert (`ClientsCnt = 0` ≠ Problem, `CachePr = 0` ≠
   Inaktivität, `COMPLIANT` ≠ OS-Aktualität, Cache-Inaktivität nur bei
   `ServedDelta = 0` UND `OriginDelta = 0`).
5. **Vollständigkeitspflicht.** Tabellen werden bei vielen Standorten
   stillschweigend abgeschnitten. Eine explizite Anweisung im Prompt
   reduziert dieses Risiko.

---

## Bekannte Fallen bei MS Copilot Basic im Browser

**Stilles Halluzinieren bei großen Dateien.** Copilot kürzt
Eingabedateien intern, ohne es zuverlässig zu kommunizieren. Aggregate
werden teilweise erfunden – selbstbewusst, plausibel, falsch.

**Mustererkennung statt Rechnen.** Copilot fixiert sich gerne auf ein
Einzelsignal und konstruiert daraus eine Geschichte, ohne sie mit den
übrigen Signalen abzugleichen.

**Tabellenabschneidung.** Bei vielen Standorten oder vielen Spalten
endet die Ausgabe stillschweigend mittendrin.

**Selektive Regelbefolgung.** Pflicht-Markierungen werden nicht
zuverlässig befolgt – auch wenn Copilot in der Antwort darauf verweist.
Reihenfolge- und Strukturvorgaben werden dagegen verlässlich umgesetzt.

**Fehlende Selbstkenntnis.** Copilot weiß nicht, dass es die
Browser-Basic-Version ist, und meldet seine Limitierungen inkonsistent.

---

## Methodische Konsequenzen

**Vor-Aggregation ist Pflicht, keine Optimierung.** Sobald Copilot mehr
als zwei Dateien oder Datenreihen über mehrere Tage sieht, muss
vorgerechnet werden. `AssetCache_Verdichten_Co.ps1` reduziert die
Zeilenzahl um rund 75 %, der Verlauf bleibt erhalten. Bei längeren
Zeiträumen (etwa „eine Woche nach iOS-Update") wird auch das knapp; eine
zwei-stufige Übergabe (Aggregat-Datei für Übersicht, Detail-Datei für
Verlauf) ist die wahrscheinlich nächste Stufe.

**Der Prompt ist ein lebendes Dokument.** Jede neue Datenkonstellation
kann eine neue Fehlerklasse zeigen. Die Vorgehensweise „Realität gegen
Copilot-Antwort prüfen, Gegenanweisung formulieren" wird wiederholt
nötig sein.

**Klein und fein, animieren statt zwingen.** Die Reihenfolge-Anweisung
hat sich mehrfach als wirksamer erwiesen als jede Pflichtregel. Diese
Grundphilosophie sollte beibehalten werden.

---

## Versuchungen beim Nachschärfen

Wenn die nächste Auswertungsrunde Fehler zeigt, ist die natürliche
Reaktion: noch eine Regel hinzufügen. Diese Versuchung sollte bewusst
ausgehalten werden. Regeln summieren sich, machen den Prompt schwerer
und konkurrieren irgendwann mit der Reihenfolge-Erkenntnis.

Stattdessen die Frage in dieser Reihenfolge:

1. Ist es ein Datenproblem oder ein Prompt-Problem?
2. Wenn Prompt-Problem: lässt es sich durch Reihenfolge lösen, nicht
   durch eine zusätzliche Regel?
3. Wenn doch eine Regel nötig ist: gehört sie ins Datenmodell
   (Gegenanweisung zu einer beobachteten Fehlinterpretation) oder ins
   Auswertungs-Prompt (methodische Vorgabe)?

---

## Phasen der Entwicklung (chronologisch)

Der heutige Prompt ist in sechs Phasen entstanden. Die Phasen sind hier
nur grob skizziert; die einzelnen Lehren stehen oben.

**Phase 1 – Strukturelle Schärfung:** Scope-Regel, Vollständigkeitspflicht,
Trennung COMPLIANT von OS-Aktualität. Strukturtreue verbessert,
inhaltliche Bewertung blieb unzuverlässig.

**Phase 2 – Domänenwissen:** Datenmodell-Abschnitt mit erklärten Spalten.
Erstmals belastbare Wissensbasis statt nur Anweisungen.

**Phase 3 – Methodischer Rahmen:** Hypothesen-Haltung, keine
Schuldzuweisungen. Tonangabe, kein technischer Fix.

**Phase 4 – Reihenfolge statt Regeln:** Der Wendepunkt. Aggregat-Tabelle
als erzwungener erster Schritt.

**Phase 5 – Anti-Halluzinations-Vorbereitung:** Vor-Aggregation per
Skript, Hinweise auf 15-Minuten- und Stunden-Variante im Prompt.

**Phase 6 – Gegenanweisungen:** Jede beobachtete Fehlinterpretation
bekam eine explizite Gegenanweisung im Datenmodell.
