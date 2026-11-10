Upstream: https://github.com/amnezia-vpn/amneziawg-apple/tree/9d5ee60edefa95b933a738dd7cda671dd18021fc

MIT WireGuardKit/Go bridge subset. Kept source copyright notices and COPYING. Removed app/UI and Go Xray bridge; app has a separate sing-box extension to avoid linking two Go runtimes. Parser copied into AWG extension with explicit WireGuardKit import. Go static library is built in CI from pinned go.mod/go.sum, not committed as binary.
