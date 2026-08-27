import * as zebar from "zebar";
import { createStore } from "solid-js/store";
import { onCleanup, onMount, useContext } from "solid-js";
import { createContext, ParentProps } from "solid-js";

/** Provider group for all built-in zebar providers. */
export const providers = zebar.createProviderGroup({
  cpu: { type: "cpu" },
  memory: { type: "memory" },
  weather: { type: "weather" },
  date: { type: "date", formatting: "EEE d MMM HH:mm" },
  glazewm: { type: "glazewm" },
  komorebi: { type: "komorebi" },
  keyboard: { type: "keyboard" },
  media: { type: "media" },
  tray: { type: "systray" },
  battery: { type: "battery" },
});

/** Combined provider output type. */
export type Providers = Partial<typeof providers.outputMap>;

/** Solid context carrying the reactive provider store. */
export const ProvidersContext = createContext(providers.outputMap);

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
  const [output, setOutput] = createStore(providers.outputMap);

  let wmProvider: zebar.GlazeWmProvider | zebar.KomorebiProvider | undefined;

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
  });

  onCleanup(() => {
    providers.stopAll();
    wmProvider?.stop();
  });

  return (
    <ProvidersContext.Provider value={output}>
      {props.children}
    </ProvidersContext.Provider>
  );
}
