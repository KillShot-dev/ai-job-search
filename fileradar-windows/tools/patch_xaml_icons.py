from pathlib import Path

p = Path(__file__).resolve().parents[1] / "FileRadar" / "Views" / "MainPage.xaml"
t = p.read_text(encoding="utf-8")

subs = [
(
'''                    <FontIcon Glyph="&#xE71B;" FontSize="15" Foreground="{StaticResource FrAccentBrush}" />
                    <TextBlock x:Name="BrandText" Text="FileRadar" FontSize="14" FontWeight="SemiBold"
                               Foreground="{StaticResource FrTextBrush}" />''',
'''                    <Image x:Name="BrandIcon" Width="22" Height="22" Stretch="Uniform" />
                    <TextBlock x:Name="BrandText" Text="FileRadar" FontSize="14" FontWeight="SemiBold"
                               Foreground="{StaticResource FrTextBrush}" />'''
),
(
'''                    <Button x:Name="AppearanceBtn" Click="AppearanceBtn_Click" Style="{StaticResource FrQuietChip}"
                            ToolTipService.ToolTip="Appearance  ·  Ctrl+Shift+A"
                            Background="Transparent" Foreground="{StaticResource FrMutedBrush}">
                        <FontIcon x:Name="AppearanceIcon" Glyph="&#xE708;" FontSize="14" />
                    </Button>''',
'''                    <Button x:Name="AppearanceBtn" Click="AppearanceBtn_Click" Style="{StaticResource FrQuietChip}"
                            ToolTipService.ToolTip="Appearance  ·  Ctrl+Shift+A"
                            Background="Transparent" Foreground="{StaticResource FrMutedBrush}">
                        <Image x:Name="AppearanceIconImg" Width="22" Height="22" Stretch="Uniform" />
                    </Button>'''
),
(
'''                    <Button x:Name="ChromeBtn" Click="ChromeBtn_Click" Style="{StaticResource FrQuietChip}"
                            ToolTipService.ToolTip="Chrome / Layout  ·  Ctrl+Shift+C"
                            Background="Transparent" Foreground="{StaticResource FrAccentBrush}">
                        <FontIcon Glyph="&#xE8A7;" FontSize="14" />
                    </Button>''',
'''                    <Button x:Name="ChromeBtn" Click="ChromeBtn_Click" Style="{StaticResource FrQuietChip}"
                            ToolTipService.ToolTip="Chrome / Layout  ·  Ctrl+Shift+C"
                            Background="Transparent" Foreground="{StaticResource FrAccentBrush}">
                        <Image x:Name="ChromeIconImg" Width="22" Height="22" Stretch="Uniform" />
                    </Button>'''
),
(
'''                    <Button x:Name="DualPaneBtn" Click="DualPaneBtn_Click" Style="{StaticResource FrQuietChip}"
                            ToolTipService.ToolTip="Dual pane  ·  Ctrl+\ "
                            Background="Transparent" Foreground="{StaticResource FrAccentBrush}">
                        <FontIcon x:Name="DualPaneIcon" Glyph="&#xE7C4;" FontSize="14" />
                    </Button>''',
'''                    <Button x:Name="DualPaneBtn" Click="DualPaneBtn_Click" Style="{StaticResource FrQuietChip}"
                            ToolTipService.ToolTip="Dual pane  ·  Ctrl+\ "
                            Background="Transparent" Foreground="{StaticResource FrAccentBrush}">
                        <Image x:Name="DualPaneIconImg" Width="22" Height="22" Stretch="Uniform" />
                    </Button>'''
),
(
'''                    <Button x:Name="ViewModeBtn" Click="ViewModeBtn_Click" Style="{StaticResource FrQuietChip}"
                            ToolTipService.ToolTip="List / grid  ·  Ctrl+1 / Ctrl+2"
                            Background="Transparent" Foreground="{StaticResource FrMutedBrush}">
                        <FontIcon Glyph="&#xE8A9;" FontSize="14" />
                    </Button>''',
'''                    <Button x:Name="ViewModeBtn" Click="ViewModeBtn_Click" Style="{StaticResource FrQuietChip}"
                            ToolTipService.ToolTip="List / grid  ·  Ctrl+1 / Ctrl+2"
                            Background="Transparent" Foreground="{StaticResource FrMutedBrush}">
                        <Image x:Name="ViewModeIconImg" Width="22" Height="22" Stretch="Uniform" />
                    </Button>'''
),
(
'''                    <Button x:Name="SyncBtn" Click="CompareSync_Click" Style="{StaticResource FrQuietChip}"
                            ToolTipService.ToolTip="Compare / Sync between panes"
                            Background="Transparent" Foreground="{StaticResource FrMutedBrush}">
                        <FontIcon Glyph="&#xE895;" FontSize="14" />
                    </Button>''',
'''                    <Button x:Name="SyncBtn" Click="CompareSync_Click" Style="{StaticResource FrQuietChip}"
                            ToolTipService.ToolTip="Compare / Sync between panes"
                            Background="Transparent" Foreground="{StaticResource FrMutedBrush}">
                        <Image x:Name="SyncIconImg" Width="22" Height="22" Stretch="Uniform" />
                    </Button>'''
),
(
'''                    <Button x:Name="InspectorBtn" Click="InspectorBtn_Click" Style="{StaticResource FrQuietChip}"
                            ToolTipService.ToolTip="Toggle inspector  ·  Ctrl+Alt+I"
                            Background="Transparent" Foreground="{StaticResource FrMutedBrush}">
                        <FontIcon Glyph="&#xE8A1;" FontSize="14" />
                    </Button>''',
'''                    <Button x:Name="InspectorBtn" Click="InspectorBtn_Click" Style="{StaticResource FrQuietChip}"
                            ToolTipService.ToolTip="Toggle inspector  ·  Ctrl+Alt+I"
                            Background="Transparent" Foreground="{StaticResource FrMutedBrush}">
                        <Image x:Name="InspectorIconImg" Width="22" Height="22" Stretch="Uniform" />
                    </Button>'''
),
(
'''                    <Button x:Name="TransfersBtn" Click="TransfersBtn_Click" Style="{StaticResource FrQuietChip}"
                            ToolTipService.ToolTip="Activities / Transfers  ·  Ctrl+Shift+T"
                            Background="Transparent" Foreground="{StaticResource FrMutedBrush}">
                        <FontIcon Glyph="&#xE8AB;" FontSize="14" />
                    </Button>''',
'''                    <Button x:Name="TransfersBtn" Click="TransfersBtn_Click" Style="{StaticResource FrQuietChip}"
                            ToolTipService.ToolTip="Activities / Transfers  ·  Ctrl+Shift+T"
                            Background="Transparent" Foreground="{StaticResource FrMutedBrush}">
                        <Image x:Name="TransfersIconImg" Width="22" Height="22" Stretch="Uniform" />
                    </Button>'''
),
(
'''                    <Button x:Name="OverflowBtn" Click="OverflowBtn_Click" Style="{StaticResource FrQuietChip}"
                            ToolTipService.ToolTip="More — rename, shortcuts, workspace, shelves"
                            Background="Transparent" Foreground="{StaticResource FrMutedBrush}">
                        <FontIcon Glyph="&#xE712;" FontSize="14" />
                    </Button>''',
'''                    <Button x:Name="OverflowBtn" Click="OverflowBtn_Click" Style="{StaticResource FrQuietChip}"
                            ToolTipService.ToolTip="More — rename, shortcuts, workspace, shelves"
                            Background="Transparent" Foreground="{StaticResource FrMutedBrush}">
                        <Image x:Name="OverflowIconImg" Width="22" Height="22" Stretch="Uniform" />
                    </Button>'''
),
]

# Command rail buttons
rail = [
("Home", "&#xE80F;", "RailHomeImg"),
("Search", "&#xE721;", "RailSearchImg"),
("Sync", "&#xE895;", "RailSyncImg"),
("Transfers", "&#xE8AB;", "RailXferImg"),
("Settings", "&#xE713;", "RailPrefsImg"),
]
# Simpler: replace each FontIcon inside command rail with named image via unique glyph blocks

rail_subs = [
(
'''                            <FontIcon Glyph="&#xE80F;" FontSize="16" HorizontalAlignment="Center" />
                            <TextBlock Text="Home" FontSize="9" HorizontalAlignment="Center" />''',
'''                            <Image x:Name="RailHomeImg" Width="28" Height="28" Stretch="Uniform" HorizontalAlignment="Center" />
                            <TextBlock Text="Home" FontSize="9" HorizontalAlignment="Center" />'''
),
(
'''                            <FontIcon Glyph="&#xE721;" FontSize="16" HorizontalAlignment="Center" />
                            <TextBlock Text="Search" FontSize="9" HorizontalAlignment="Center" />''',
'''                            <Image x:Name="RailSearchImg" Width="28" Height="28" Stretch="Uniform" HorizontalAlignment="Center" />
                            <TextBlock Text="Search" FontSize="9" HorizontalAlignment="Center" />'''
),
(
'''                            <FontIcon Glyph="&#xE895;" FontSize="16" HorizontalAlignment="Center" />
                            <TextBlock Text="Sync" FontSize="9" HorizontalAlignment="Center" />''',
'''                            <Image x:Name="RailSyncImg" Width="28" Height="28" Stretch="Uniform" HorizontalAlignment="Center" />
                            <TextBlock Text="Sync" FontSize="9" HorizontalAlignment="Center" />'''
),
(
'''                            <FontIcon Glyph="&#xE8AB;" FontSize="16" HorizontalAlignment="Center" />
                            <TextBlock Text="Xfer" FontSize="9" HorizontalAlignment="Center" />''',
'''                            <Image x:Name="RailXferImg" Width="28" Height="28" Stretch="Uniform" HorizontalAlignment="Center" />
                            <TextBlock Text="Xfer" FontSize="9" HorizontalAlignment="Center" />'''
),
(
'''                            <FontIcon Glyph="&#xE713;" FontSize="16" HorizontalAlignment="Center" />
                            <TextBlock Text="Prefs" FontSize="9" HorizontalAlignment="Center" />''',
'''                            <Image x:Name="RailPrefsImg" Width="28" Height="28" Stretch="Uniform" HorizontalAlignment="Center" />
                            <TextBlock Text="Prefs" FontSize="9" HorizontalAlignment="Center" />'''
),
]

nav_subs = [
(
'''                            <Button x:Name="NavHome" Tag="Home" Click="Nav_Click" Style="{StaticResource FrNavButton}">
                                <StackPanel Orientation="Horizontal" Spacing="8">
                                    <FontIcon Glyph="&#xE8B7;" FontSize="13" />
                                    <TextBlock Text="Browser" FontSize="12" />
                                </StackPanel>
                            </Button>''',
'''                            <Button x:Name="NavHome" Tag="Home" Click="Nav_Click" Style="{StaticResource FrNavButton}">
                                <StackPanel Orientation="Horizontal" Spacing="8">
                                    <Image x:Name="NavHomeImg" Width="20" Height="20" Stretch="Uniform" />
                                    <TextBlock Text="Browser" FontSize="12" VerticalAlignment="Center" />
                                </StackPanel>
                            </Button>'''
),
(
'''                            <Button Tag="Shelves" Click="Nav_Click" Style="{StaticResource FrNavButton}">
                                <StackPanel Orientation="Horizontal" Spacing="8">
                                    <FontIcon Glyph="&#xE8B9;" FontSize="13" />
                                    <TextBlock Text="Shelves" FontSize="12" />
                                </StackPanel>
                            </Button>''',
'''                            <Button Tag="Shelves" Click="Nav_Click" Style="{StaticResource FrNavButton}">
                                <StackPanel Orientation="Horizontal" Spacing="8">
                                    <Image x:Name="NavShelvesImg" Width="20" Height="20" Stretch="Uniform" />
                                    <TextBlock Text="Shelves" FontSize="12" VerticalAlignment="Center" />
                                </StackPanel>
                            </Button>'''
),
(
'''                            <Button Tag="Search" Click="Nav_Click" Style="{StaticResource FrNavButton}">
                                <StackPanel Orientation="Horizontal" Spacing="8">
                                    <FontIcon Glyph="&#xE721;" FontSize="13" />
                                    <TextBlock Text="Search" FontSize="12" />
                                </StackPanel>
                            </Button>''',
'''                            <Button Tag="Search" Click="Nav_Click" Style="{StaticResource FrNavButton}">
                                <StackPanel Orientation="Horizontal" Spacing="8">
                                    <Image x:Name="NavSearchImg" Width="20" Height="20" Stretch="Uniform" />
                                    <TextBlock Text="Search" FontSize="12" VerticalAlignment="Center" />
                                </StackPanel>
                            </Button>'''
),
(
'''                            <Button Tag="Cleanup" Click="Nav_Click" Style="{StaticResource FrNavButton}">
                                <StackPanel Orientation="Horizontal" Spacing="8">
                                    <FontIcon Glyph="&#xE894;" FontSize="13" />
                                    <TextBlock Text="Cleanup" FontSize="12" />
                                </StackPanel>
                            </Button>''',
'''                            <Button Tag="Cleanup" Click="Nav_Click" Style="{StaticResource FrNavButton}">
                                <StackPanel Orientation="Horizontal" Spacing="8">
                                    <Image x:Name="NavCleanupImg" Width="20" Height="20" Stretch="Uniform" />
                                    <TextBlock Text="Cleanup" FontSize="12" VerticalAlignment="Center" />
                                </StackPanel>
                            </Button>'''
),
(
'''                            <Button Tag="Duplicates" Click="Nav_Click" Style="{StaticResource FrNavButton}">
                                <StackPanel Orientation="Horizontal" Spacing="8">
                                    <FontIcon Glyph="&#xE8C8;" FontSize="13" />
                                    <TextBlock Text="Duplicates" FontSize="12" />
                                </StackPanel>
                            </Button>''',
'''                            <Button Tag="Duplicates" Click="Nav_Click" Style="{StaticResource FrNavButton}">
                                <StackPanel Orientation="Horizontal" Spacing="8">
                                    <Image x:Name="NavDuplicatesImg" Width="20" Height="20" Stretch="Uniform" />
                                    <TextBlock Text="Duplicates" FontSize="12" VerticalAlignment="Center" />
                                </StackPanel>
                            </Button>'''
),
(
'''                            <Button Tag="Timeline" Click="Nav_Click" Style="{StaticResource FrNavButton}">
                                <StackPanel Orientation="Horizontal" Spacing="8">
                                    <FontIcon Glyph="&#xE787;" FontSize="13" />
                                    <TextBlock Text="Timeline" FontSize="12" />
                                </StackPanel>
                            </Button>''',
'''                            <Button Tag="Timeline" Click="Nav_Click" Style="{StaticResource FrNavButton}">
                                <StackPanel Orientation="Horizontal" Spacing="8">
                                    <Image x:Name="NavTimelineImg" Width="20" Height="20" Stretch="Uniform" />
                                    <TextBlock Text="Timeline" FontSize="12" VerticalAlignment="Center" />
                                </StackPanel>
                            </Button>'''
),
(
'''                            <Button Tag="Workspaces" Click="Nav_Click" Style="{StaticResource FrNavButton}">
                                <StackPanel Orientation="Horizontal" Spacing="8">
                                    <FontIcon Glyph="&#xE8A9;" FontSize="13" />
                                    <TextBlock Text="Workspaces" FontSize="12" />
                                </StackPanel>
                            </Button>''',
'''                            <Button Tag="Workspaces" Click="Nav_Click" Style="{StaticResource FrNavButton}">
                                <StackPanel Orientation="Horizontal" Spacing="8">
                                    <Image x:Name="NavWorkspacesImg" Width="20" Height="20" Stretch="Uniform" />
                                    <TextBlock Text="Workspaces" FontSize="12" VerticalAlignment="Center" />
                                </StackPanel>
                            </Button>'''
),
(
'''                            <Button Tag="RecycleBin" Click="Nav_Click" Style="{StaticResource FrNavButton}">
                                <StackPanel Orientation="Horizontal" Spacing="8">
                                    <FontIcon Glyph="&#xE74D;" FontSize="13" />
                                    <TextBlock Text="Recycle Bin" FontSize="12" />
                                </StackPanel>
                            </Button>''',
'''                            <Button Tag="RecycleBin" Click="Nav_Click" Style="{StaticResource FrNavButton}">
                                <StackPanel Orientation="Horizontal" Spacing="8">
                                    <Image x:Name="NavRecycleImg" Width="20" Height="20" Stretch="Uniform" />
                                    <TextBlock Text="Recycle Bin" FontSize="12" VerticalAlignment="Center" />
                                </StackPanel>
                            </Button>'''
),
(
'''                                        <FontIcon Glyph="&#xE74C;" FontSize="11" Foreground="{StaticResource FrMutedBrush}" />
                                        <TextBlock Text="Drop Stack" FontSize="11" FontWeight="SemiBold"
                                                   Foreground="{StaticResource FrTextBrush}" />''',
'''                                        <Image x:Name="DropStackIconImg" Width="18" Height="18" Stretch="Uniform" />
                                        <TextBlock Text="Drop Stack" FontSize="11" FontWeight="SemiBold"
                                                   Foreground="{StaticResource FrTextBrush}" VerticalAlignment="Center" />'''
),
(
'''                                <FontIcon Glyph="&#xE8AB;" FontSize="14" Foreground="White" />''',
'''                                <Image x:Name="SyncPillIconImg" Width="20" Height="20" Stretch="Uniform" />'''
),
(
'''                        <FontIcon x:Name="HudIcon" Glyph="&#xE8C8;" FontSize="18"
                                  Foreground="{StaticResource FrAccentBrush}" VerticalAlignment="Center" />''',
'''                        <Image x:Name="HudIconImg" Width="28" Height="28" Stretch="Uniform" VerticalAlignment="Center" />'''
),
(
'''                                    <FontIcon x:Name="InspectorGlyph" Glyph="&#xE8A5;" FontSize="36"
                                              HorizontalAlignment="Center" VerticalAlignment="Center"
                                              Foreground="{StaticResource FrMutedBrush}" />''',
'''                                    <Image x:Name="InspectorGlyphImg" Width="72" Height="72" Stretch="Uniform"
                                              HorizontalAlignment="Center" VerticalAlignment="Center" />'''
),
(
'''                                <FontIcon Glyph="&#xE8B7;" FontSize="13" />
                                <TextBlock Text="Show in Explorer" />''',
'''                                <Image x:Name="ShowInExplorerIconImg" Width="18" Height="18" Stretch="Uniform" />
                                <TextBlock Text="Show in Explorer" VerticalAlignment="Center" />'''
),
(
'''                        <TextBlock Text="Queue" FontSize="14" FontWeight="SemiBold"
                                   Foreground="{StaticResource FrTextBrush}" />''',
'''                        <StackPanel Orientation="Horizontal" Spacing="8">
                            <Image x:Name="QueueIconImg" Width="22" Height="22" Stretch="Uniform" />
                            <TextBlock Text="Queue" FontSize="14" FontWeight="SemiBold"
                                       Foreground="{StaticResource FrTextBrush}" VerticalAlignment="Center" />
                        </StackPanel>'''
),
]

for a, b in subs + rail_subs + nav_subs:
    if a not in t:
        print("MISS:\n", a[:120].replace("\n", " "))
    else:
        t = t.replace(a, b)
        print("OK")

p.write_text(t, encoding="utf-8")
print("patched", p)
