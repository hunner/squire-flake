// c1:integration-ci

package sync_test

// AGNT-1161 reproduction: does the "Resync tools" button's underlying
// activity chain (SyncActivities.MaterializeMCPToolsFromUnion, invoked by
// DiscoverToolsForIdentityWorkflow, invoked by ConnectorConductorServer's
// KickToolDiscoveryForIdentity, invoked by MCPServerService.ResyncTools) fan
// out a newly-discovered tool into an AppEntitlementProxyBinding for a caller
// who already holds the connector's default "All approved tools" toolset
// grant?
//
// This calls the exact SyncActivities method the resync-triggered Temporal
// workflow calls (not the lower-level mcp.ReconcileTools/ReconcileDefaultProfiles
// helpers directly, and not a mocked activity), against a live
// DynamoDB+Postgres utest.Integration environment, to settle whether the
// reconcile path really is wired end-to-end today.

import (
	"testing"

	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/timestamppb"

	mcpconnector "gitlab.com/ductone/c1/pkg/connector/mcp"
	aigovctrl "gitlab.com/ductone/c1/pkg/controller/ai_governance/controller"
	"gitlab.com/ductone/c1/pkg/ctxotel"
	"gitlab.com/ductone/c1/pkg/db"
	mdai "gitlab.com/ductone/c1/pkg/models/ai_governance"
	mdapp "gitlab.com/ductone/c1/pkg/models/app"
	"gitlab.com/ductone/c1/pkg/passport"
	pbai "gitlab.com/ductone/c1/pkg/pb/c1/models/ai_governance/v1"
	pbapi "gitlab.com/ductone/c1/pkg/pb/c1/models/api/v1"
	pbapp "gitlab.com/ductone/c1/pkg/pb/c1/models/app/v1"
	syncactivity "gitlab.com/ductone/c1/pkg/temporal/sync_activity/sync"
	"gitlab.com/ductone/c1/pkg/utest"
)

type AGNT1161ResyncFanoutSuite struct {
	suite.Suite
	utest.Integration

	env *utest.Env
}

func TestAGNT1161ResyncFanoutSuite(t *testing.T) {
	suite.Run(t, &AGNT1161ResyncFanoutSuite{})
}

func (s *AGNT1161ResyncFanoutSuite) SetupSuite() {
	s.Require().Nil(s.env)
	s.env = s.NewSuiteEnvironment(s.T(), nil)
}

func (s *AGNT1161ResyncFanoutSuite) TearDownSuite() {
	if s.env != nil {
		s.env.Close()
		s.env = nil
	}
}

func (s *AGNT1161ResyncFanoutSuite) BeforeTest(_, _ string) {
	utest.NewFixtures(s.T(), s.env)
}

func (s *AGNT1161ResyncFanoutSuite) AfterTest(suiteName, testName string) {
	s.env.AfterTest(suiteName, testName)
}

// TestResyncNewTool_FansOutIntoExistingToolsetGrant reproduces the exact
// scenario AGNT-1161 describes: a caller already holds a grant on the
// connector's default "All approved tools" toolset. A resync (per-identity
// discovery) surfaces one BRAND NEW tool the caller never saw before -- as if
// they just re-authorized and the upstream now exposes another tool. We drive
// this through SyncActivities.MaterializeMCPToolsFromUnion, the exact
// activity DiscoverToolsForIdentityWorkflow invokes after
// DiscoverToolsForIdentity, and assert the new tool ends up with an
// AppEntitlementProxyBinding fanned out from the toolset entitlement --
// i.e. that the resync path (not just the periodic sync path) creates the
// binding inline, without waiting for a later sync.
func (s *AGNT1161ResyncFanoutSuite) TestResyncNewTool_FansOutIntoExistingToolsetGrant() {
	r := s.Require()

	ctx := s.env.Context()
	tenant := s.env.Fixtures().Basic(ctx)
	tenantID := tenant.TenantID()
	pp := tenant.SystemOwner().Passport(passport.ServiceInternal, "")
	ctx = passport.Set(ctx, pp)

	database := s.env.Fixtures().DB
	tenantReader := s.env.Fixtures().TenantReader()
	pgDriver := s.env.Fixtures().Postgres

	// --- Seed: app + external, per-user, auto-approving MCP connector. ---
	app, err := mdapp.NewApp(ctx, pp, "AGNT-1161 Test App", "", nil, 0)
	r.NoError(err)
	r.NoError(database.Put(ctx, app))
	appID := app.GetId()

	cfgAny, err := anypb.New(&pbai.ExternalHostedMCPConfig{
		// Force auto-approve regardless of tenant default so a newly
		// discovered tool is immediately eligible for the default "All
		// approved tools" toolset -- isolates the fan-out question from the
		// separate admin-approval-queue question.
		RequireToolApproval: pbai.OptionalBool_OPTIONAL_BOOL_FALSE,
	})
	r.NoError(err)
	connector, err := mdapp.NewConnector(ctx, pp, "", appID, "AGNT-1161 External MCP", "", nil, &pbapp.ConnectorConfig{Config: cfgAny})
	r.NoError(err)
	r.NoError(database.Put(ctx, connector))
	connectorID := connector.GetId()

	// --- Drivers wired exactly as SyncActivities' wire.Struct would. ---
	mcpToolDriver := &aigovctrl.Driver{Tracer: ctxotel.Tracer(ctx, "mcp_tool"), DB: database}
	mcpToolSeenDriver := &aigovctrl.MCPToolSeenDriver{Tracer: ctxotel.Tracer(ctx, "mcp_tool_seen"), DB: database}
	mcpRawSignalDriver := &aigovctrl.MCPToolRawSignalDriver{Tracer: ctxotel.Tracer(ctx, "mcp_tool_raw_signal"), DB: database}
	profileDriver := &aigovctrl.AccessProfileDriver{Tracer: ctxotel.Tracer(ctx, "mcp_access_profile"), DB: database, PG: pgDriver}
	bindingDriver := &aigovctrl.AccessProfileToolBindingDriver{
		Tracer:              ctxotel.Tracer(ctx, "mcp_access_profile_tool_binding"),
		DB:                  database,
		AccessProfileDriver: profileDriver,
	}
	settingsDriver := &aigovctrl.AIGovernanceSettingsDriver{Tracer: aigovctrl.AIGovernanceSettingsTraceProvider(ctx), DB: database}
	connAppCtrl := s.env.Controllers().ConnectorApp(ctx).WithPassport(pp)

	activities := &syncactivity.SyncActivities{
		DB:                                database,
		TenantReader:                      tenantReader,
		ConnectorAppDriver:                s.env.Controllers().ConnectorApp(ctx),
		MCPToolDriver:                     mcpToolDriver,
		MCPToolSeenDriver:                 mcpToolSeenDriver,
		MCPToolRawSignalDriver:            mcpRawSignalDriver,
		MCPAccessProfileDriver:            profileDriver,
		MCPAccessProfileToolBindingDriver: bindingDriver,
		AIGovernanceSettingsDriver:        settingsDriver,
	}

	// --- Step 1: one tool already exists (pre-resync baseline) and the
	// caller already holds the connector's default "All approved tools"
	// toolset grant -- this is the steady state before the user hits Resync. ---
	seenExisting := mdai.NewMCPToolSeen(tenantID, appID, connectorID, "sentinel", "list_widgets", 1, "list widgets", "{}", "", "", "")
	_, err = mcpToolSeenDriver.WithPassport(pp).Upsert(ctx, seenExisting)
	r.NoError(err)

	changed, err := activities.MaterializeMCPToolsFromUnion(ctx, pp, appID, connectorID, true)
	r.NoError(err)
	r.True(changed, "first materialize should create the baseline tool")

	allApprovedProfile, err := profileDriver.WithPassport(pp).Get(ctx, appID, connectorID, mcpconnector.DefaultAccessProfileAllApprovedID)
	r.NoError(err)
	toolsetEntID := mdai.EffectiveAppEntitlementID(allApprovedProfile)
	r.NotEmpty(toolsetEntID)

	now := timestamppb.Now()
	toolsetAE := &pbapp.AppEntitlement{
		TenantId:    tenantID,
		Id:          toolsetEntID,
		AppId:       appID,
		DisplayName: allApprovedProfile.GetDisplayName(),
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	r.NoError(database.Put(ctx, toolsetAE))

	appUser, err := mdapp.NewAppUser(ctx, pp, appID, "AGNT-1161 test user", "", nil, make(map[string]string), false)
	r.NoError(err)
	r.NoError(database.Put(ctx, appUser))

	grantReason, err := mdapp.NewGrantReasonSystemManaged(ctx, appID, toolsetEntID, appUser.GetId())
	r.NoError(err)
	r.NoError(connAppCtrl.GrantAppEntitlement(ctx, toolsetAE, appUser.GetId(), nil, grantReason))

	// --- Step 2: the resync button is pressed. In real life this dispatches
	// KickToolDiscoveryForIdentity -> DiscoverToolsForIdentityWorkflow, which
	// runs DiscoverToolsForIdentity (writes this identity's MCPToolSeen view --
	// simulated here directly since it just requires a live upstream MCP
	// server) then MaterializeMCPToolsFromUnion (called for real, below). The
	// upstream now also exposes a brand new tool the caller never saw before. ---
	seenNew := mdai.NewMCPToolSeen(tenantID, appID, connectorID, "sentinel", "delete_widget", 1, "delete a widget", "{}", "", "", "")
	_, err = mcpToolSeenDriver.WithPassport(pp).Upsert(ctx, seenNew)
	r.NoError(err)

	changed, err = activities.MaterializeMCPToolsFromUnion(ctx, pp, appID, connectorID, true)
	r.NoError(err)
	r.True(changed, "resync materialize must report the new tool as a change")

	toolCtrl := mcpToolDriver.WithPassport(pp)
	tools, _, err := toolCtrl.List(ctx, appID, connectorID, &pbapi.PaginationRequest{PageSize: 100})
	r.NoError(err)
	var newTool *pbai.MCPTool
	for _, t := range tools {
		if t.GetToolName() == "delete_widget" {
			newTool = t
		}
	}
	r.NotNil(newTool, "the newly discovered tool must have been reconciled into MCPTool")
	r.Equal(pbai.MCPToolState_MCP_TOOL_STATE_APPROVED, newTool.GetState(), "auto-approve connector config should land the new tool APPROVED")
	r.NotEmpty(newTool.GetAppEntitlementId(), "an approved tool must have an AppEntitlement")

	// --- The assertion AGNT-1161 is about: did the resync path fan the
	// existing toolset grant out to the new tool via an
	// AppEntitlementProxyBinding, the same way the periodic connector sync
	// does -- or did it only touch MCPTool and leave the new tool
	// unreachable through the toolset grant until a later sync? ---
	proxyKey := &pbapp.AppEntitlementProxyBinding{
		TenantId:            tenantID,
		SrcAppId:            appID,
		SrcAppEntitlementId: toolsetEntID,
		DstAppId:            appID,
		DstAppEntitlementId: newTool.GetAppEntitlementId(),
	}
	err = database.GetOne(ctx, proxyKey, db.WithExcludeDeleted())
	r.NoError(err, "AGNT-1161: MaterializeMCPToolsFromUnion (the resync path's activity) must create the "+
		"AppEntitlementProxyBinding fanning the existing toolset grant out to the newly discovered tool")
}
