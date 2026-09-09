import * as zebar from "zebar";
import { createStore } from "solid-js/store";
import { onCleanup, onMount, useContext } from "solid-js";
import { createContext, ParentProps } from "solid-js";

/**
 * Provider group for the built-in system providers.
 *
 * The window-manager provider (GlazeWM/Komorebi) is intentionally NOT part of
 * this group. It is created separately as {@link wmProvider} so there is only
 * ever a single WM subscription, and so it can be restarted independently if
 * its backend subscription drops.
 */
export const providers = zebar.createProviderGroup({
  cpu: { type: "cpu" },
  memory: { type: "memory" },
  weather: { type: "weather" },
  date: { type: "date", formatting: "EEE d MMM HH:mm" },
  keyboard: { type: "keyboard" },
  media: { type: "media" },
  tray: { type: "systray" },
  battery: { type: "battery" },
});

/**
 * Combined provider output type: the system provider group outputs plus the
 * optional window-manager output keyed by its type.
 */
export type Providers = Partial<typeof providers.outputMap> & {
  glazewm?: zebar.GlazeWmOutput;
  komorebi?: zebar.KomorebiOutput;
};

/** Solid context carrying the reactive provider store. */
export const ProvidersContext = createContext<Providers>(providers.outputMap);

/**
 * Returns the current provider outputs from context.
 */
export function useProviders() {
  return useContext(ProvidersContext);
}

/**
 * Wraps children with provider context, initializing all zebar providers
 * and forwarding their outputs into a reactive store.
 */
export function ProvidersProvider(
  props: ParentProps<{ WmType?: "glazewm" | "komorebi" }>,
) {
  const [output, setOutput] = createStore<Providers>(providers.outputMap);

  let wmProvider: zebar.GlazeWmProvider | zebar.KomorebiProvider | undefined;
  let wmKeepAlive: ReturnType<typeof setInterval> | undefined;

  if (props.WmType === "glazewm") {
    wmProvider = zebar.createProvider({ type: "glazewm" });
  } else if (props.WmType === "komorebi") {
    wmProvider = zebar.createProvider({ type: "komorebi" });
  }

  onMount(() => {
    providers.onOutput((outputMap) => setOutput(outputMap));
    wmProvider?.onOutput((outputMap) =>
      setOutput((prev) => ({ ...prev, [props.WmType!]: outputMap }))
    );
    // Restart the provider on error so it re-subscribes and resumes emitting.
    wmProvider?.onError(() => {
      void wmProvider?.restart();
    });
    // Komorebi (and GlazeWM) silently drop a subscriber when a notification
    // write to it fails; afterwards zebar receives no further events and no
    // error fires, so the workspace indicator freezes until zebar restarts.
    // Periodically restart the provider as a safety net: each restart
    // re-subscribes AND re-fetches the current state, so the bar self-corrects
    // within this interval even after a silent drop. The widget keys
    // workspaces by index, so re-emitting an unchanged state reuses DOM nodes
    // and produces no visible flicker.
    let restarting = false;
    wmKeepAlive = setInterval(async () => {
      if (restarting) return; // avoid overlapping restarts
      restarting = true;
      try {
        await wmProvider?.restart();
      } finally {
        restarting = false;
      }
    }, 10_000);
  });

  onCleanup(() => {
    if (wmKeepAlive !== undefined) {
      clearInterval(wmKeepAlive);
    }
    providers.stopAll();
    wmProvider?.stop();
  });

  return (
    <ProvidersContext.Provider value={output}>
      {props.children}
    </ProvidersContext.Provider>
  );
}
