# Velo per iPhone

**Chat private, cifrate, solo tra voi: la versione iOS di [Velo](https://velochat.eu).**
Parla con la [Velo per Android](https://github.com/castieldev85/velo-android) usando la stessa
cifratura post-quantistica e lo stesso Tor incorporato.

[English below](#velo-for-iphone-english)

> **Stato: in sviluppo.** Non è ancora sull'App Store e non ci sono versioni pronte da scaricare.
> Il codice è pubblico per trasparenza e per la licenza AGPL.

## Cosa fa già

- **Tor dentro l'app.** I messaggi viaggiano solo dentro Tor verso il server `.onion` del gruppo,
  senza nessuna richiesta DNS fuori da Tor.
- **OMEMO2 post-quantistico** (scambio di chiavi ibrido classico + ML-KEM-1024, libsignal),
  compatibile con la Velo per Android; codice di verifica dei contatti uguale a quello Android.
- **Messaggi:** messaggi a tempo, foto e video a visualizzazione singola (invio e ricezione),
  elimina per tutti, svuota la cronologia anche sul telefono dell'altro, storie di 24 ore.
- **Sicurezza del telefono:** PIN di sblocco, PIN antipanico, cancellazione automatica, contenuto
  escluso dagli screenshot, copertura nell'elenco delle app, notifiche senza testo, cancellazione a
  distanza su comando dell'amministratore del gruppo.
- **Interfaccia di Velo:** temi e personalizzazione come su Android, stato di Tor sempre visibile,
  dettagli dei contatti e impostazioni nello stile Velo.

Su iPhone le notifiche push richiedono un account sviluppatore Apple: per ora Velo usa
l'aggiornamento in background di iOS e, in prova, un'opzione "Sempre collegata".

## Compilare

La compilazione gira su GitHub Actions (runner macOS con Xcode recente): `build-libsignal-ios.yml`
prepara libsignal per iPhone, `build-ios.yml` produce un IPA non firmato. Gli indirizzi del server
non sono nel codice: il workflow li prende dai segreti del repository `VELO_LOGIN_DOMAIN`,
`VELO_ONION_HOST`, `VELO_BUNDLE_ID`, e cifra l'IPA con `IPA_PASSPHRASE` (un repository pubblico
mostra a tutti gli artifact). L'IPA si installa firmandolo, per esempio con Sideloadly.
Requisiti: iOS 17 o più recente.

## Licenza e origine

Velo per iPhone è un fork di [Monal](https://github.com/monal-im/Monal) (BSD 2-Clause, vedi
`LICENSE`), a cui va il nostro grazie. Velo aggiunge
[libsignal](https://github.com/signalapp/libsignal) (fork
[pq-omemo-2](https://codeberg.org/monocles/pq-omemo-2), AGPLv3), Tor
([Tor.framework di iCepa](https://github.com/iCepa/Tor.framework)) e il proprio codice: l'app nel suo
insieme è distribuita sotto **GNU AGPLv3** (vedi `LICENSE-AGPL-3.0.txt`). Velo non è collegata al
progetto Monal: per problemi di Velo non contattare gli sviluppatori di Monal, apri una Issue qui.

## Come è fatta

Velo è sviluppata da una persona con l'aiuto di un assistente di intelligenza artificiale
(Claude di Anthropic), che scrive gran parte del codice. Ogni versione viene provata su un iPhone vero,
e il codice è pubblico proprio perché chiunque possa controllarlo. Velo non ha ancora avuto una
revisione di sicurezza indipendente; per le vulnerabilità vedi [SECURITY.md](SECURITY.md).

Niente screenshot per ora: Velo per iPhone esclude di proposito il proprio contenuto dalle catture
dello schermo. Le schermate della versione Android sono nel
[suo repository](https://github.com/castieldev85/velo-android).

---

# Velo for iPhone (English)

**Private chats, encrypted, just between you: the iOS version of [Velo](https://velochat.eu).**
It talks to [Velo for Android](https://github.com/castieldev85/velo-android) with the same
post-quantum encryption and the same built-in Tor.

> **Status: in development.** Not on the App Store yet and no ready-made builds to download.

**Already working:** Tor inside the app (messages only through Tor to the group's `.onion` server, no
DNS outside Tor); OMEMO2 with hybrid classical + ML-KEM-1024 key exchange, compatible with Velo for
Android, same contact verification code; disappearing messages, view-once photos and videos, delete
for everyone, clear history on both phones, 24-hour stories; app lock PIN, panic PIN, automatic wipe,
screenshot protection, content-free notifications, remote wipe by the group admin; Velo themes, Tor
status, Velo-style contact details and settings.

**Build:** GitHub Actions (`build-libsignal-ios.yml`, then `build-ios.yml`) produce an unsigned IPA.
Server addresses are not in the code: they come from the repository secrets `VELO_LOGIN_DOMAIN`,
`VELO_ONION_HOST`, `VELO_BUNDLE_ID`, and the IPA artifact is encrypted with `IPA_PASSPHRASE`. iOS 17+.

**License:** a fork of [Monal](https://github.com/monal-im/Monal) (BSD 2-Clause, see `LICENSE`), with
libsignal (AGPLv3), Tor.framework and Velo's own code; the app as a whole is distributed under the
**GNU AGPLv3** (see `LICENSE-AGPL-3.0.txt`). Velo is not affiliated with the Monal project: please
report Velo issues here, not to the Monal developers.

**How it is made:** Velo is developed by one person with the help of an AI assistant (Anthropic's
Claude), which writes much of the code. Every version is tested on a real iPhone, and the code is
public so that anyone can review it. No independent security audit yet; for vulnerabilities see
[SECURITY.md](SECURITY.md). No screenshots for now: Velo for iPhone deliberately hides its content
from screen captures (Android screenshots are in its repository).
