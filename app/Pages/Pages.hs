module Pages.Pages where
import Network.Wai (Response, Request (pathInfo), responseBuilder, responseFile)
import IHP.HSX.QQ (hsx)
import Text.Blaze.Html (Html)
import Text.Regex (Regex, mkRegex, matchRegex)
import Network.HTTP.Types (status404, status200)
import Blaze.ByteString.Builder (copyByteString)
import Data.ByteString.UTF8 (fromString)
import Text.Blaze.Html.Renderer.String (renderHtml)
import Layout (layout)
import Logger (info, warning)
import System.Directory (doesFileExist)
import Data.List (intercalate, find)
import Api.Api (api)
import Pages.Contact.Contact (contact)
import Pages.Sources.Sources (sources)
import Pages.Guestbook.Guestbook (guestbook)
import Pages.Projects.Projects (projects)
import Pages.Projects.Snake (leaderboard)
import Pages.Admin.Admin (admin)
import Index (index)
import Data.Text (unpack)
import Pages.Search.Search (search)
import Page
import Scripts (testPage)

page404 :: [String] -> Html
page404 args = layout [hsx|
    <h1>404 - Page not found</h1><br>
    params: {args}
|]

pages :: [Page]
pages = [
            search pages,
            admin,
            contact,
            sources,
            guestbook,
            projects,
            leaderboard,
            testPage,
            index
        ]

findPage :: String -> Page
findPage addr = case find (\(settings, _) -> case do 
    if route settings == "/" && addr /= "/" then Nothing 
    else matchRegex (mkRegex (route settings)) addr of
        Nothing -> False
        _ -> True) pages of
        (Just page) -> page
        Nothing -> ([], \req -> return $ page404 (map unpack $ pathInfo req))