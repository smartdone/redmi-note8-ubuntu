#!/usr/bin/env python3
# Generates kernel/patches/0010: defer the WCN3990 STA vdev start until the
# BSS peer exists (WLAN.HL.3.0.2 rejects vdev start before that).
# Usage: ath10k-wcn3990-defer-vdev-start.py <kernel tree>
import sys
root = sys.argv[1]

def edit(path, pairs):
    p = f"{root}/{path}"
    s = open(p).read()
    for old, new in pairs:
        assert s.count(old) == 1, (path, old[:70])
        s = s.replace(old, new)
    open(p, "w").write(s)

edit("drivers/net/wireless/ath/ath10k/core.h", [(
"""	bool is_started;
	bool is_up;
""",
"""	bool is_started;
	bool is_up;
	/* WCN3990 STA: vdev start deferred until the BSS peer exists */
	bool vdev_start_pending;
	struct cfg80211_chan_def pending_chandef;
""")])

edit("drivers/net/wireless/ath/ath10k/mac.c", [
# helper, placed before assign_vif_chanctx
("""static int ath10k_sta_state(struct ieee80211_hw *hw,""",
"""/*
 * WCN3990 firmware (seen with WLAN.HL.3.0.2 on SM6125) answers a station
 * vdev start with status -1 until the peer for the BSS exists, so the
 * interface never authenticates. Start the vdev right after the BSS peer is
 * created instead of at channel context assignment.
 */
static bool ath10k_mac_defer_vdev_start(struct ath10k *ar,
					struct ieee80211_vif *vif)
{
	return QCA_REV_WCN3990(ar) && vif->type == NL80211_IFTYPE_STATION &&
	       !vif->p2p;
}

static int ath10k_mac_start_deferred_vdev(struct ath10k_vif *arvif,
					  const u8 *peer_addr)
{
	struct ath10k *ar = arvif->ar;
	int ret;

	lockdep_assert_held(&ar->conf_mutex);

	if (!arvif->vdev_start_pending)
		return 0;

	ret = ath10k_vdev_start(arvif, &arvif->pending_chandef);
	if (ret) {
		ath10k_warn(ar, "failed delayed vdev %d start after peer %pM: %d\\n",
			    arvif->vdev_id, peer_addr, ret);
		return ret;
	}

	arvif->vdev_start_pending = false;
	arvif->is_started = true;
	ath10k_dbg(ar, ATH10K_DBG_MAC,
		   "wcn3990 delayed vdev %u start after BSS peer\\n",
		   arvif->vdev_id);

	ret = ath10k_mac_vif_setup_ps(arvif);
	if (ret)
		ath10k_warn(ar, "failed to update vdev %i ps: %d\\n",
			    arvif->vdev_id, ret);

	if (ath10k_mac_can_set_cts_prot(arvif)) {
		ret = ath10k_mac_set_cts_prot(arvif);
		if (ret)
			ath10k_warn(ar, "failed to set cts protection for vdev %d: %d\\n",
				    arvif->vdev_id, ret);
	}

	return 0;
}

static int ath10k_sta_state(struct ieee80211_hw *hw,"""),
# defer in assign
("""	if (WARN_ON(arvif->is_started)) {
		mutex_unlock(&ar->conf_mutex);
		return -EBUSY;
	}

	ret = ath10k_vdev_start(arvif, &ctx->def);""",
"""	if (WARN_ON(arvif->is_started)) {
		mutex_unlock(&ar->conf_mutex);
		return -EBUSY;
	}

	if (ath10k_mac_defer_vdev_start(ar, vif)) {
		arvif->pending_chandef = ctx->def;
		arvif->vdev_start_pending = true;
		ath10k_dbg(ar, ATH10K_DBG_MAC,
			   "wcn3990 defer vdev %u start until BSS peer\\n",
			   arvif->vdev_id);
		mutex_unlock(&ar->conf_mutex);
		return 0;
	}

	ret = ath10k_vdev_start(arvif, &ctx->def);"""),
# unassign: never started
("""		   "mac chanctx unassign ptr %p vdev_id %i\\n",
		   ctx, arvif->vdev_id);

	WARN_ON(!arvif->is_started);""",
"""		   "mac chanctx unassign ptr %p vdev_id %i\\n",
		   ctx, arvif->vdev_id);

	if (arvif->vdev_start_pending) {
		/* the BSS peer never came, the vdev was never started */
		arvif->vdev_start_pending = false;
		mutex_unlock(&ar->conf_mutex);
		return;
	}

	WARN_ON(!arvif->is_started);"""),
# start after the BSS peer was created
("""		arsta->peer_id = find_first_bit(peer->peer_ids,
						ATH10K_MAX_NUM_PEER_IDS);

		spin_unlock_bh(&ar->data_lock);

		if (!sta->tdls)
			goto exit;""",
"""		arsta->peer_id = find_first_bit(peer->peer_ids,
						ATH10K_MAX_NUM_PEER_IDS);

		spin_unlock_bh(&ar->data_lock);

		if (vif->type == NL80211_IFTYPE_STATION && !sta->tdls &&
		    arvif->vdev_start_pending) {
			ret = ath10k_mac_start_deferred_vdev(arvif, sta->addr);
			if (ret) {
				ath10k_peer_delete(ar, arvif->vdev_id, sta->addr);
				ath10k_mac_dec_num_stations(arvif, sta);
				kfree(arsta->tx_stats);
				goto exit;
			}
		}

		if (!sta->tdls)
			goto exit;"""),
])
print("patched")
