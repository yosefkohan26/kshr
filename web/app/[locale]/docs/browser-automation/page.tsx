import { useTranslations } from "next-intl";
import { getTranslations } from "next-intl/server";
import { buildAlternates } from "../../../../i18n/seo";
import { CodeBlock } from "../../components/code-block";

export async function generateMetadata({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "docs.browserAutomation" });
  return {
    title: t("metaTitle"),
    description: t("metaDescription"),
    alternates: buildAlternates(locale, "/docs/browser-automation"),
  };
}

export default function BrowserAutomationPage() {
  const t = useTranslations("docs.browserAutomation");

  return (
    <>
      <h1>{t("title")}</h1>
      <p>{t("intro")}</p>

      <h2>{t("commandIndex")}</h2>
      <table>
        <thead>
          <tr>
            <th>{t("categoryHeader")}</th>
            <th>{t("subcommandsHeader")}</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td>{t("navAndTargeting")}</td>
            <td>
              <code>identify</code>, <code>open</code>, <code>open-split</code>,{" "}
              <code>navigate</code>, <code>back</code>, <code>forward</code>,{" "}
              <code>reload</code>, <code>url</code>, <code>focus-webview</code>,{" "}
              <code>is-webview-focused</code>
            </td>
          </tr>
          <tr>
            <td>{t("waiting")}</td>
            <td>
              <code>wait</code>
            </td>
          </tr>
          <tr>
            <td>{t("domInteraction")}</td>
            <td>
              <code>click</code>, <code>dblclick</code>, <code>hover</code>,{" "}
              <code>focus</code>, <code>check</code>, <code>uncheck</code>,{" "}
              <code>scroll-into-view</code>, <code>type</code>, <code>fill</code>,{" "}
              <code>press</code>, <code>keydown</code>, <code>keyup</code>,{" "}
              <code>select</code>, <code>scroll</code>
            </td>
          </tr>
          <tr>
            <td>{t("inspection")}</td>
            <td>
              <code>snapshot</code>, <code>screenshot</code>, <code>get</code>,{" "}
              <code>is</code>, <code>find</code>, <code>highlight</code>
            </td>
          </tr>
          <tr>
            <td>{t("jsAndInjection")}</td>
            <td>
              <code>eval</code>, <code>addinitscript</code>, <code>addscript</code>,{" "}
              <code>addstyle</code>
            </td>
          </tr>
          <tr>
            <td>{t("framesDialogsDownloads")}</td>
            <td>
              <code>frame</code>, <code>dialog</code>, <code>download</code>
            </td>
          </tr>
          <tr>
            <td>{t("stateAndSession")}</td>
            <td>
              <code>cookies</code>, <code>storage</code>, <code>state</code>
            </td>
          </tr>
          <tr>
            <td>{t("tabsAndLogs")}</td>
            <td>
              <code>tab</code>, <code>console</code>, <code>errors</code>
            </td>
          </tr>
        </tbody>
      </table>

      <h2>{t("targetingSurface")}</h2>
      <p>{t("targetingDesc")}</p>
      <CodeBlock lang="bash">{`# Open a new browser split
kshr browser open https://example.com

# Discover focused IDs and browser metadata
kshr browser identify
kshr browser identify --surface surface:2

# Positional vs flag targeting are equivalent
kshr browser surface:2 url
kshr browser --surface surface:2 url`}</CodeBlock>

      <h2>{t("navigation")}</h2>
      <CodeBlock lang="bash">{`kshr browser open https://example.com
kshr browser open-split https://news.ycombinator.com

kshr browser surface:2 navigate https://example.org/docs --snapshot-after
kshr browser surface:2 back
kshr browser surface:2 forward
kshr browser surface:2 reload --snapshot-after
kshr browser surface:2 url

kshr browser surface:2 focus-webview
kshr browser surface:2 is-webview-focused`}</CodeBlock>

      <h2>{t("waitingSection")}</h2>
      <p>{t("waitingDesc")}</p>
      <CodeBlock lang="bash">{`kshr browser surface:2 wait --load-state complete --timeout-ms 15000
kshr browser surface:2 wait --selector "#checkout" --timeout-ms 10000
kshr browser surface:2 wait --text "Order confirmed"
kshr browser surface:2 wait --url-contains "/dashboard"
kshr browser surface:2 wait --function "window.__appReady === true"`}</CodeBlock>

      <h2>{t("domSection")}</h2>
      <p>{t("domDesc")}</p>
      <CodeBlock lang="bash">{`kshr browser surface:2 click "button[type='submit']" --snapshot-after
kshr browser surface:2 dblclick ".item-row"
kshr browser surface:2 hover "#menu"
kshr browser surface:2 focus "#email"
kshr browser surface:2 check "#terms"
kshr browser surface:2 uncheck "#newsletter"
kshr browser surface:2 scroll-into-view "#pricing"

kshr browser surface:2 type "#search" "kshr"
kshr browser surface:2 fill "#email" --text "ops@example.com"
kshr browser surface:2 fill "#email" --text ""
kshr browser surface:2 press Enter
kshr browser surface:2 keydown Shift
kshr browser surface:2 keyup Shift
kshr browser surface:2 select "#region" "us-east"
kshr browser surface:2 scroll --dy 800 --snapshot-after
kshr browser surface:2 scroll --selector "#log-view" --dx 0 --dy 400`}</CodeBlock>

      <h2>{t("inspectionSection")}</h2>
      <p>{t("inspectionDesc")}</p>
      <CodeBlock lang="bash">{`kshr browser surface:2 snapshot --interactive --compact
kshr browser surface:2 snapshot --selector "main" --max-depth 5
kshr browser surface:2 screenshot --out /tmp/kshr-page.png

kshr browser surface:2 get title
kshr browser surface:2 get url
kshr browser surface:2 get text "h1"
kshr browser surface:2 get html "main"
kshr browser surface:2 get value "#email"
kshr browser surface:2 get attr "a.primary" --attr href
kshr browser surface:2 get count ".row"
kshr browser surface:2 get box "#checkout"
kshr browser surface:2 get styles "#total" --property color

kshr browser surface:2 is visible "#checkout"
kshr browser surface:2 is enabled "button[type='submit']"
kshr browser surface:2 is checked "#terms"

kshr browser surface:2 find role button --name "Continue"
kshr browser surface:2 find text "Order confirmed"
kshr browser surface:2 find label "Email"
kshr browser surface:2 find placeholder "Search"
kshr browser surface:2 find alt "Product image"
kshr browser surface:2 find title "Open settings"
kshr browser surface:2 find testid "save-btn"
kshr browser surface:2 find first ".row"
kshr browser surface:2 find last ".row"
kshr browser surface:2 find nth 2 ".row"

kshr browser surface:2 highlight "#checkout"`}</CodeBlock>

      <h2>{t("jsSection")}</h2>
      <CodeBlock lang="bash">{`kshr browser surface:2 eval "document.title"
kshr browser surface:2 eval --script "window.location.href"

kshr browser surface:2 addinitscript "window.__kshrReady = true;"
kshr browser surface:2 addscript "document.querySelector('#name')?.focus()"
kshr browser surface:2 addstyle "#debug-banner { display: none !important; }"`}</CodeBlock>

      <h2>{t("stateSection")}</h2>
      <p>{t("stateDesc")}</p>
      <CodeBlock lang="bash">{`kshr browser surface:2 cookies get
kshr browser surface:2 cookies get --name session_id
kshr browser surface:2 cookies set session_id abc123 --domain example.com --path /
kshr browser surface:2 cookies clear --name session_id
kshr browser surface:2 cookies clear --all

kshr browser surface:2 storage local set theme dark
kshr browser surface:2 storage local get theme
kshr browser surface:2 storage local clear
kshr browser surface:2 storage session set flow onboarding
kshr browser surface:2 storage session get flow

kshr browser surface:2 state save /tmp/kshr-browser-state.json
kshr browser surface:2 state load /tmp/kshr-browser-state.json`}</CodeBlock>

      <h2>{t("tabsSection")}</h2>
      <p>{t("tabsDesc")}</p>
      <CodeBlock lang="bash">{`kshr browser surface:2 tab list
kshr browser surface:2 tab new https://example.com/pricing

# Switch by index or by target surface
kshr browser surface:2 tab switch 1
kshr browser surface:2 tab switch surface:7

# Close current tab or a specific target
kshr browser surface:2 tab close
kshr browser surface:2 tab close surface:7`}</CodeBlock>

      <h2>{t("consoleSection")}</h2>
      <CodeBlock lang="bash">{`kshr browser surface:2 console list
kshr browser surface:2 console clear

kshr browser surface:2 errors list
kshr browser surface:2 errors clear`}</CodeBlock>

      <h2>{t("dialogsSection")}</h2>
      <CodeBlock lang="bash">{`kshr browser surface:2 dialog accept
kshr browser surface:2 dialog accept "Confirmed by automation"
kshr browser surface:2 dialog dismiss`}</CodeBlock>

      <h2>{t("framesSection")}</h2>
      <CodeBlock lang="bash">{`# Enter an iframe context
kshr browser surface:2 frame "iframe[name='checkout']"
kshr browser surface:2 click "#pay-now"

# Return to the top-level document
kshr browser surface:2 frame main`}</CodeBlock>

      <h2>{t("downloadsSection")}</h2>
      <CodeBlock lang="bash">{`kshr browser surface:2 click "a#download-report"
kshr browser surface:2 download --path /tmp/report.csv --timeout-ms 30000`}</CodeBlock>

      <h2>{t("commonPatterns")}</h2>

      <h3>{t("patternNavigate")}</h3>
      <CodeBlock lang="bash">{`kshr browser open https://example.com/login
kshr browser surface:2 wait --load-state complete --timeout-ms 15000
kshr browser surface:2 snapshot --interactive --compact
kshr browser surface:2 get title`}</CodeBlock>

      <h3>{t("patternForm")}</h3>
      <CodeBlock lang="bash">{`kshr browser surface:2 fill "#email" --text "ops@example.com"
kshr browser surface:2 fill "#password" --text "$PASSWORD"
kshr browser surface:2 click "button[type='submit']" --snapshot-after
kshr browser surface:2 wait --text "Welcome"
kshr browser surface:2 is visible "#dashboard"`}</CodeBlock>

      <h3>{t("patternDebug")}</h3>
      <CodeBlock lang="bash">{`kshr browser surface:2 console list
kshr browser surface:2 errors list
kshr browser surface:2 screenshot --out /tmp/kshr-failure.png
kshr browser surface:2 snapshot --interactive --compact`}</CodeBlock>

      <h3>{t("patternSession")}</h3>
      <CodeBlock lang="bash">{`kshr browser surface:2 state save /tmp/session.json
# ...later...
kshr browser surface:2 state load /tmp/session.json
kshr browser surface:2 reload`}</CodeBlock>
    </>
  );
}
