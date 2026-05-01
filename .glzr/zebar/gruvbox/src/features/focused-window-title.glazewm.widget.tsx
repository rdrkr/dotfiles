import { createMemo } from "solid-js";
import { GroupItem } from "@components/group.component";
import { useProviders } from "@providers/index";

export function FocusedWindowTitleGlazewmWidget() {
  const providers = useProviders();
  const isCurrentMonitor = createMemo(
    () =>
      providers.komorebi?.focusedMonitor.id ===
      providers.komorebi?.currentMonitor.id,
  );

  const title = createMemo(() => {
    const workspace = providers.komorebi?.focusedWorkspace;
    if (!workspace) return "-";
    
    if (workspace.maximizedWindow) {
      return workspace.maximizedWindow.title ?? "-";
    }
    
    if (workspace.monocleContainer && workspace.monocleContainer.windows.length > 0) {
      return workspace.monocleContainer.windows[workspace.monocleContainer.windows.length - 1]?.title ?? "-";
    }
    
    const containerIndex = workspace.focusedContainerIndex;
    if (workspace.tilingContainers && workspace.tilingContainers.length > containerIndex) {
       const container = workspace.tilingContainers[containerIndex];
       if (container && container.windows.length > 0) {
           return container.windows[0]?.title ?? "-";
       }
    }
    
    if (workspace.floatingWindows && workspace.floatingWindows.length > 0) {
       return workspace.floatingWindows[workspace.floatingWindows.length - 1]?.title ?? "-";
    }

    return "-";
  });

  return (
    <GroupItem class="text-ellipsis whitespace-nowrap max-w-[200px] 2xl:max-w-[350px] lg:max-w-[200px]">
      <span
        title={title()}
        classList={{
          "text-gruvbox-muted hover:text-inherit": !isCurrentMonitor(),
        }}
      >
        {title()}
      </span>
    </GroupItem>
  );
}
