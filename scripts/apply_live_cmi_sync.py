from pathlib import Path

p = Path("index.html")
s = p.read_text(encoding="utf-8")

def replace_once(before, after):
    global s
    if before not in s:
        raise RuntimeError("Expected application anchor missing: " + before[:100])
    if s.count(before) != 1:
        raise RuntimeError("Ambiguous application anchor: " + before[:100])
    s = s.replace(before, after, 1)

replace_once("  let sharedStateLoaded = false;", """  let sharedStateLoaded = false;
  let cmiSharedLiveChannel = null;
  let cmiSharedRefreshTimer = null;
  let cmiSharedRefreshPending = false;
  let cmiSharedRefreshInFlight = false;
  let cmiSharedSaveInFlight = false;
  let cmiSharedPollTimer = null;
  let cmiLastSharedSavedAt = '';

  function broadcastCmiDashboardChange(event) {
    if (!cmiSharedLiveChannel) return;
    void cmiSharedLiveChannel.send({
      type: 'broadcast', event,
      payload: { at: new Date().toISOString() }
    }).catch(error => console.warn('CMI live notification failed:', error));
  }

  async function reloadCmiSharedDashboard() {
    if (!currentDashboardUser || cmiSharedSaveInFlight || sharedStateSyncTimer) {
      cmiSharedRefreshPending = true;
      return;
    }
    if (cmiSharedRefreshInFlight) {
      cmiSharedRefreshPending = true;
      return;
    }
    cmiSharedRefreshInFlight = true;
    try {
      const {data, error} = await supabaseClient.rpc('dashboard_get_shared_state');
      if (error) throw error;
      if (data) {
        const payload = typeof data === 'string' ? JSON.parse(data) : data;
        if (payload.savedAt !== cmiLastSharedSavedAt) {
          mergeSharedState(payload);
          cmiLastSharedSavedAt = payload.savedAt || '';
        }
      }
      // Latest Responsibility is stored separately from shared register status.
      latestResponsibilityLoaded = false;
      await loadLatestResponsibilities();
      renderAll();
    } catch (error) {
      console.error('CMI shared-dashboard refresh failed:', error);
    } finally {
      cmiSharedRefreshInFlight = false;
      if (cmiSharedRefreshPending && !cmiSharedSaveInFlight && !sharedStateSyncTimer) {
        cmiSharedRefreshPending = false;
        queueCmiSharedDashboardRefresh();
      }
    }
  }

  function queueCmiSharedDashboardRefresh() {
    if (cmiSharedRefreshTimer) clearTimeout(cmiSharedRefreshTimer);
    cmiSharedRefreshTimer = setTimeout(() => {
      cmiSharedRefreshTimer = null;
      void reloadCmiSharedDashboard();
    }, 150);
  }

  function startCmiSharedDashboardSync() {
    if (cmiSharedLiveChannel) return;
    cmiSharedLiveChannel = supabaseClient.channel('rwanda-cmi-dashboard-register-live')
      .on('broadcast', {event: 'shared-state-saved'}, queueCmiSharedDashboardRefresh)
      .on('broadcast', {event: 'responsibility-saved'}, queueCmiSharedDashboardRefresh)
      .subscribe(status => {
        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT')
          console.warn('CMI dashboard live channel:', status);
      });
    // Reconcile missed messages and reconnecting/late-joining sessions.
    cmiSharedPollTimer = setInterval(() => {
      if (!document.hidden) queueCmiSharedDashboardRefresh();
    }, 15000);
    window.addEventListener('focus', queueCmiSharedDashboardRefresh);
  }""")
replace_once("     startRfiRealtimeSubscription();", "     startRfiRealtimeSubscription();\n     startCmiSharedDashboardSync();")
replace_once("       sharedStateLoaded=!!loaded;\n       return !!loaded;", "       sharedStateLoaded=!!loaded;\n       if(loaded)cmiLastSharedSavedAt=payload.savedAt||'';\n       return !!loaded;")
replace_once("  async function saveSharedDashboardState(skipRemoteMerge=false) {\n     try{", "  async function saveSharedDashboardState(skipRemoteMerge=false) {\n     cmiSharedSaveInFlight=true;\n     try{") if "  async function saveSharedDashboardState(skipRemoteMerge=false) {\n     try{" in s else replace_once("  async function saveSharedDashboardState(skipRemoteMerge=false) {\n    try{", "  async function saveSharedDashboardState(skipRemoteMerge=false) {\n    cmiSharedSaveInFlight=true;\n    try{")
replace_once("       if(error)console.error('Unable to update shared dashboard state:',error);\n     }catch(e){console.error('Shared dashboard state save failed:',e)}", "       if(error)console.error('Unable to update shared dashboard state:',error);\n       else {cmiLastSharedSavedAt=payload.savedAt||'';broadcastCmiDashboardChange('shared-state-saved')}\n     }catch(e){console.error('Shared dashboard state save failed:',e)}\n     finally{cmiSharedSaveInFlight=false;if(cmiSharedRefreshPending){cmiSharedRefreshPending=false;queueCmiSharedDashboardRefresh()}}") if "       if(error)console.error('Unable to update shared dashboard state:',error);\n     }catch(e)" in s else replace_once("       if(error)console.error('Unable to update shared dashboard state:',error);\n    }catch(e){console.error('Shared dashboard state save failed:',e)}", "       if(error)console.error('Unable to update shared dashboard state:',error);\n       else {cmiLastSharedSavedAt=payload.savedAt||'';broadcastCmiDashboardChange('shared-state-saved')}\n    }catch(e){console.error('Shared dashboard state save failed:',e)}\n    finally{cmiSharedSaveInFlight=false;if(cmiSharedRefreshPending){cmiSharedRefreshPending=false;queueCmiSharedDashboardRefresh()}}")
replace_once("     sharedStateSyncTimer=setTimeout(()=>{saveSharedDashboardState()},250);", "     sharedStateSyncTimer=setTimeout(()=>{sharedStateSyncTimer=null;void saveSharedDashboardState()},250);")
replace_once("   latestResponsibilityValues.set(id,data.latest_responsibility);", "   latestResponsibilityValues.set(id,data.latest_responsibility);\n   renderClientDashboard();\n   broadcastCmiDashboardChange('responsibility-saved');")
# Preserve the team's existing unique-CMI priority rules and row-based values.
# Include reopened CMIs when calculating the dedicated team agreed/submitted panels.
replace_once("if(latestResponsibilityValue(r)!=='CMI Team'||cmiCurrentStatusValue(r)!==config.status)continue;", "if(!['CMI Team','ReOpen - CMI Team'].includes(latestResponsibilityValue(r))||cmiCurrentStatusValue(r)!==config.status)continue;")
p.write_text(s, encoding="utf-8")
print("Patched Executive Dashboard live synchronization")
