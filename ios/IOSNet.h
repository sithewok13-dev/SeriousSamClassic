/* Multiplayer on the phone's Wi-Fi: its own address (for others to join a
   game it hosts) and the addresses a LAN search asks (GameAgent.cpp). */
#ifndef IOSNET_H
#define IOSNET_H

#ifdef __cplusplus
extern "C" {
#endif

/* The phone's address on its Wi-Fi (or on the Personal Hotspot it shares),
   as "192.168.1.23", into str. 0 if it has none (no Wi-Fi). */
int IOSNet_LocalAddress(char *str, int size);

/* Every address on the local networks the phone is on (Wi-Fi, its hotspot),
   in network byte order, at most ctMax. A network bigger than 1022
   addresses is searched only around the phone (its /24). iOS sends no
   broadcasts without an entitlement sideloaded apps can't get, so a LAN
   search asks each address in turn. Returns how many. */
int IOSNet_LanTargets(unsigned int *aulAddr, int ctMax);

/* Sends one small packet onto the Wi-Fi, so iOS asks for Local Network
   access now (the Network menu opens, a game is hosted) rather than in the
   middle of a search or of someone joining. Until it's answered, everything
   sent there is dropped. */
void IOSNet_AskLocalNetwork(void);

#ifdef __cplusplus
}
#endif

#endif
