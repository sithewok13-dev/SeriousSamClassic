/* Multiplayer on the phone's Wi-Fi. See IOSNet.h. */
#include "IOSNet.h"

#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>

/* The networks other players can be on: Wi-Fi (en0 on a phone), the
   Personal Hotspot the phone shares (bridge100), a wired adapter. Never
   mobile data (pdp_ip), VPNs (utun, ipsec), AirDrop (awdl, llw) or the
   loopback. Lower is better. -1: not one. */
static int IOSNet_Rank(const struct ifaddrs *ifa)
{
  static const char *const astrSkip[] = { "lo", "pdp_ip", "utun", "ipsec", "awdl", "llw", "ap", "gif", "stf", "anpi", NULL };
  if (ifa->ifa_addr == NULL || ifa->ifa_addr->sa_family != AF_INET || ifa->ifa_netmask == NULL) return -1;
  if (!(ifa->ifa_flags & IFF_UP) || (ifa->ifa_flags & IFF_LOOPBACK)) return -1;
  /* (a self-assigned 169.254 address: no network others can reach it on) */
  if ((ntohl(((const struct sockaddr_in *)ifa->ifa_addr)->sin_addr.s_addr) >> 16) == 0xA9FE) return -1;
  for (int i = 0; astrSkip[i]; i++) {
    if (strncmp(ifa->ifa_name, astrSkip[i], strlen(astrSkip[i])) == 0) return -1;
  }
  if (strcmp(ifa->ifa_name, "en0") == 0) return 0;
  if (strncmp(ifa->ifa_name, "bridge", 6) == 0) return 1;
  if (strncmp(ifa->ifa_name, "en", 2) == 0) return 2;
  return 3;
}

int IOSNet_LocalAddress(char *str, int size)
{
  struct ifaddrs *pList = NULL;
  if (size > 0) str[0] = 0;
  if (getifaddrs(&pList) != 0) return 0;
  int iBest = -1;
  struct in_addr adrBest;
  for (struct ifaddrs *ifa = pList; ifa; ifa = ifa->ifa_next) {
    const int iRank = IOSNet_Rank(ifa);
    if (iRank < 0 || (iBest >= 0 && iRank >= iBest)) continue;
    iBest = iRank;
    adrBest = ((const struct sockaddr_in *)ifa->ifa_addr)->sin_addr;
  }
  freeifaddrs(pList);
  if (iBest < 0) return 0;
  snprintf(str, size, "%s", inet_ntoa(adrBest));
  return 1;
}

/* Adds the host addresses of one network (host byte order) */
static int IOSNet_AddNetwork(unsigned int ulOwn, unsigned int ulMask, unsigned int *aulAddr, int ct, int ctMax)
{
  if (~ulMask > 1023u) ulMask = 0xFFFFFF00u; /* too big: the /24 around the phone */
  const unsigned int ulNet = ulOwn & ulMask, ulLast = ulNet | ~ulMask;
  for (unsigned int ul = ulNet + 1; ul < ulLast && ct < ctMax; ul++) {
    const unsigned int ulAddr = htonl(ul);
    int bHave = 0;
    for (int i = 0; i < ct && !bHave; i++) bHave = (aulAddr[i] == ulAddr);
    if (!bHave) aulAddr[ct++] = ulAddr;
  }
  return ct;
}

int IOSNet_LanTargets(unsigned int *aulAddr, int ctMax)
{
  int ct = 0;
#ifdef IOS_CAMERA_RIG
  /* (the test rig: RIG_LAN="127.0.0.0/24" searches there instead) */
  const char *strRig = getenv("RIG_LAN");
  if (strRig && *strRig) {
    char strNet[32];
    int iBits = 24;
    if (sscanf(strRig, "%31[^/]/%d", strNet, &iBits) >= 1 && iBits >= 8 && iBits <= 30) {
      return IOSNet_AddNetwork(ntohl(inet_addr(strNet)), 0xFFFFFFFFu << (32 - iBits), aulAddr, 0, ctMax);
    }
  }
#endif
  struct ifaddrs *pList = NULL;
  if (getifaddrs(&pList) != 0) return 0;
  /* the best network first, so a cut-off list still has it */
  for (int iRank = 0; iRank <= 3; iRank++) {
    for (struct ifaddrs *ifa = pList; ifa; ifa = ifa->ifa_next) {
      if (IOSNet_Rank(ifa) != iRank) continue;
      const unsigned int ulOwn = ntohl(((const struct sockaddr_in *)ifa->ifa_addr)->sin_addr.s_addr);
      const unsigned int ulMask = ntohl(((const struct sockaddr_in *)ifa->ifa_netmask)->sin_addr.s_addr);
      ct = IOSNet_AddNetwork(ulOwn, ulMask, aulAddr, ct, ctMax);
    }
  }
  freeifaddrs(pList);
  return ct;
}

void IOSNet_AskLocalNetwork(void)
{
  unsigned int ulAddr = 0;
  if (IOSNet_LanTargets(&ulAddr, 1) < 1) return;
  const int s = socket(AF_INET, SOCK_DGRAM, 0);
  if (s < 0) return;
  struct sockaddr_in sin;
  memset(&sin, 0, sizeof(sin));
  sin.sin_family = AF_INET;
  sin.sin_addr.s_addr = ulAddr;
  sin.sin_port = htons(25601); /* (a server's query port: one that isn't there ignores it) */
  sendto(s, "\\", 1, 0, (const struct sockaddr *)&sin, sizeof(sin));
  close(s);
}
