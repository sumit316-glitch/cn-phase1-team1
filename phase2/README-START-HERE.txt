CN PROJECT — PHASE 2 CLICK-TO-RUN KIT   (team1.test)
==================================================================

ONE-TIME SETUP ON EVERY MAC
 1. Unzip into your home folder so you have  ~/cn-phase2-kit
 2. Open Terminal once and paste (lets macOS run the double-click files):
        xattr -dr com.apple.quarantine ~/cn-phase2-kit && chmod +x ~/cn-phase2-kit/*/*.command
 3. Double-click  YourMac-folder/00-my-network-info.command  -> note the IP.
 4. Put all four IPs into team.env (TextEdit). team.env must be IDENTICAL on all 4 Macs.

Then open ONLY your Mac's folder and double-click files when the run order below says.
Every window ends with ✅ or ❌. Every step saves its output in  evidence/.

ROLES
 Mac 1  primary DNS + client          Mac 2  primary edge (nginx, TLS, load balancer)
 Mac 3  Backend A + BACKUP DNS + STANDBY EDGE      Mac 4  Backend B + main client

PART 1 — REBUILD PHASE 1
 02  every Mac            install tools
 03  every Mac            ping the others
 04  Mac 1                start primary DNS
 05  Mac 3                start Backend A   (window stays open)
 06  Mac 4                start Backend B   (window stays open)
 07  Mac 2                certificates + nginx edge  -> then AirDrop from Mac 2's Desktop:
                            CN-share-for-all-Macs   -> Mac 1, 3, 4
                            CN-share-for-Mac3-only  -> Mac 3 only
 08  Mac 2, 3, 4          use the team DNS
 09  every Mac            trust the team CA, then restart Safari/Chrome
 10  Mac 4, then Mac 1    Phase 1 gate check

PART 2 — PHASE 2
 11  Mac 3                Ext A  start backup DNS
 12  ALL four Macs        Ext A  list both DNS servers
 13  Mac 4  (guided)      Ext A  failover demo   -> tells you to run 14 and 15 on Mac 1
 16  Mac 4  (guided)      Ext B  TTL demo        -> tells you to run 17 and 18 on Mac 1
 19  Mac 3 AND Mac 4      Ext C  firewall ON
 20  Mac 1, then Mac 2    Ext C  test: Mac 1 blocked, Mac 2 allowed
 21  Mac 3 AND Mac 4      Ext C  firewall OFF (rollback)
 22  Mac 4  (guided)      Ext D  HA failover demo -> Ctrl+C Backend A on Mac 3, then 05 again
 23  Mac 3                Ext E  start standby edge
 24  Mac 4  (guided)      Ext E  cutover demo    -> 25 on Mac 1, 26 on Mac 1, then 25 on Mac 3
 27  Mac 1 AND Mac 3      Ext E  roll back to the primary edge
  F  any Mac              Ext F  layer-by-layer diagnosis (use it on the faculty-injected fault)
 98  every Mac            zip evidence to the Desktop

 L-watch-...  files show live logs (good on screen during demos). Ctrl+C to stop.
