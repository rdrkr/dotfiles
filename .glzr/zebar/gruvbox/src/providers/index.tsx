import * as zebar from "zebar";
import { createStore } from "solid-js/store";
import { onCleanup, onMount, useContext } from "solid-js";
import { createContext, ParentProps } from "solid-js";

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
});

export type Providers = Partial<typeof providers.outputMap>;

export const ProvidersContext = createContext(providers.outputMap);

export function useProviders() {
  return useContext(ProvidersContext);
}

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
