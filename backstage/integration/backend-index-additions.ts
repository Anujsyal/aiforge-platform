// backstage/app/packages/backend/src/index.ts mein `backend.start();` se PEHLE ye lines add kar (guide G2).
// create-app pehle se catalog, scaffolder, scaffolder GitHub module, auth (guest) deta hai.
// Hum sirf Tech Insights (scorecards) add karte hain:
//
//   cd backstage/app
//   yarn --cwd packages/backend add @backstage-community/plugin-tech-insights-backend \
//        @backstage-community/plugin-tech-insights-backend-module-jsonfc
//   yarn --cwd packages/app add @backstage-community/plugin-tech-insights

backend.add(import('@backstage-community/plugin-tech-insights-backend'));
backend.add(import('@backstage-community/plugin-tech-insights-backend-module-jsonfc'));

// ---------------------------------------------------------------------------
// Frontend (packages/app/src/components/catalog/EntityPage.tsx), serviceEntityPage / defaultEntityPage mein ek tab:
//
//   import { EntityTechInsightsScorecardContent } from '@backstage-community/plugin-tech-insights';
//
//   <EntityLayout.Route path="/scorecard" title="Scorecard">
//     <EntityTechInsightsScorecardContent
//       title="AIForge golden-path scorecard"
//       checksId={['groupOwnerCheck', 'descriptionCheck', 'tagsCheck']}
//     />
//   </EntityLayout.Route>
