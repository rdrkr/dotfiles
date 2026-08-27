import { createMemo, Index, Show, Switch, Match } from "solid-js";
import { Motion, Presence } from "solid-motionone";
import { GroupItem } from "@components/group.component";
import { useProviders } from "@providers/index";
import { createStoredSignal } from "@/components/signal-storage.hook";
import { WorkspaceDisplayMode } from "@/components/workspaces.types";
import { FaBrandsApple } from "solid-icons/fa";
import { shellExec } from "zebar";

export function WorkspacesGlazewmWidget() {
  const providers = useProviders();

  const displayModeStorageKey = createMemo(() => {
    const deviceId = providers.komorebi?.currentMonitor.deviceId;
    if (!deviceId) {
      return undefined;
    }

    return `${deviceId}:workspaces-display-mode`;
  });

  const [displayMode, setDisplayMode] = createStoredSignal(
    WorkspaceDisplayMode.normal,
    displayModeStorageKey,
  );

  const toggleDisplayMode = () => {
    setDisplayMode(
      displayMode() === WorkspaceDisplayMode.normal
        ? WorkspaceDisplayMode.icons
        : WorkspaceDisplayMode.normal,
    );
  };

  const focusWorkspace = async (workspaceIndex: number) => {
    await shellExec(`komorebic focus-workspace ${workspaceIndex}`);
  };

  return (
    <GroupItem
      class="overflow-visible"
      onContextMenu={(e) => {
        e.preventDefault();
        toggleDisplayMode();
      }}
    >
      <FaBrandsApple class="mr-2 text-gruvbox-watermelon w-4.5 h-4.5" />
      <Index each={providers.komorebi?.currentMonitor.workspaces}>
        {(workspace, index) => (
          <Presence exitBeforeEnter>
            <Show
              when={(workspace().tilingContainers && workspace().tilingContainers.length > 0) || (workspace().floatingWindows && workspace().floatingWindows.length > 0) || index === providers.komorebi?.currentMonitor.focusedWorkspaceIndex}
            >
              <Motion.span
                class="origin-left inline-flex items-center justify-center h-full w-full py-1"
                initial={{
                  scale: 0,
                }}
                animate={{
                  scale: 1,
                }}
                exit={{
                  scale: 0.5,
                }}
              >
                <Motion.button
                  class="origin-left transition-colors h-[90%] px-2 py-2 rounded-full overflow-visible hover:bg-gruvbox-mint hover:text-gruvbox-base border-solid border-t-1 border-transparent inline-flex items-center justify-center"
                  classList={{
                    "text-gruvbox-base font-bold bg-gruvbox-watermelon": index === providers.komorebi?.currentMonitor.focusedWorkspaceIndex,
                    "px-2":
                      displayMode() === WorkspaceDisplayMode.icons &&
                      index !== providers.komorebi?.currentMonitor.focusedWorkspaceIndex,
                  }}
                  onClick={() => {
                    focusWorkspace(index);
                  }}
                  animate={{
                    fontSize:
                      displayMode() === WorkspaceDisplayMode.icons &&
                        index !== providers.komorebi?.currentMonitor.focusedWorkspaceIndex
                        ? "1.5rem"
                        : "13px",
                  }}
                  exit={{
                    fontSize: 0,
                  }}
                >
                  <Switch>
                    <Match when={displayMode() === WorkspaceDisplayMode.normal}>
                      {workspace().name ?? (index + 1).toString()}
                    </Match>
                    <Match when={displayMode() === WorkspaceDisplayMode.icons}>
                      <Show
                        when={index === providers.komorebi?.currentMonitor.focusedWorkspaceIndex}
                        fallback={
                          (workspace().name ?? (index + 1).toString())?.split(
                            " ",
                          )[0]
                        }
                      >
                        {(workspace().name ?? (index + 1).toString())?.split(
                          " ",
                        )?.[1] ??
                          workspace().name ??
                          (index + 1).toString()}
                      </Show>
                    </Match>
                  </Switch>
                </Motion.button>
              </Motion.span>
            </Show>
          </Presence>
        )}
      </Index>
    </GroupItem>
  );
}
