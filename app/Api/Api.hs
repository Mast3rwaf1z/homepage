{-# LANGUAGE OverloadedStrings #-}

module Api.Api where


import qualified Tables as T (GuestbookEntry (GuestbookEntry, EmptyGuestbook), LeaderboardEntry (EmptyLeaderboard, LeaderboardEntry), Credentials (EmptyCredentials, Credentials))
import Database.Database (getVisits, uuidExists, getGuestbook, runDb)
import Utils (unpackBS, getDefault)
import Pages.Projects.Brainfuck (code)

import IHP.HSX.QQ (hsx)
import Text.Blaze.Html (Html)

import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.UUID.V4 (nextRandom)
import Data.UUID (toString)

import Network.Wai (getRequestBodyChunk, Request (requestMethod, pathInfo))
import Network.HTTP.Types.Status (Status, status404, status200, status400)

import Data.Aeson (encode, decode, Value (String))
import Data.ByteString.Lazy (fromStrict, toStrict)
import Data.Password.Bcrypt (PasswordCheck(PasswordCheckSuccess, PasswordCheckFail), mkPassword, checkPassword, PasswordHash (PasswordHash))
import Data.Text (pack, unpack, intercalate)
import Crypto.Random (getRandomBytes)
import Data.Text.Array (Array(ByteArray))
import Text.StringRandom (stringRandomIO)
import Logger (info)
import Database.Schema (GuestbookEntry(guestbookEntryGuestbookTimestamp, guestbookEntryGuestbookName, guestbookEntryGuestbookParentId, guestbookEntryGuestbookContent, GuestbookEntry, guestbookEntryGuestbookId), Snake (Snake), User (User, userUserPassword, userUserName), Token (Token, tokenTokenToken), Visit (Visit), EntityField (UserUserName, TokenTokenName))
import Database.Persist (selectList, Entity (Entity), insertEntity, Filter (Filter), FilterValue (FilterValue), PersistFilter (BackendSpecificFilter))

import Network.HTTP.Types (HeaderName)
import Data.ByteString.UTF8 (ByteString)
import Data.Aeson.QQ (aesonQQ)
import Data.List (find)
import Text.Regex (matchRegex, mkRegex)

type Header = (HeaderName, ByteString)
type APIResponse = IO (Status, String, [Header])
type APIEndpoint = (String, Request -> APIResponse)
type APIRoute = (String, [APIEndpoint])

j2s :: Value -> String
j2s = unpackBS . toStrict .encode

defaultHeaders :: [Header]
defaultHeaders = [("Content-Type", "text/plain")]

jsonHeaders :: [Header]
jsonHeaders = [("Content-Type", "application/json")]

messageResponse :: String -> String
messageResponse value = j2s [aesonQQ|{
    "message":#{value}
}|]

apiMap :: [APIRoute]
apiMap = [
    ("POST", [
        ("/visits/new", \r -> do
            body <- getRequestBodyChunk r
            result <- uuidExists $ unpackBS body
            res <- if result then do
                time <- fmap round getPOSIXTime :: IO Int
                uuid <- nextRandom
                runDb $ insertEntity $ Visit 0 time $ toString uuid
                return $ toString uuid
            else
                return $ unpackBS body
            return (status200, j2s [aesonQQ|{"uuid":#{res}}|], jsonHeaders)
        ),
        ("/admin/login", \r -> do
            body <- getRequestBodyChunk r
            let credentials = getDefault T.EmptyCredentials (decode (fromStrict body) :: Maybe T.Credentials)
            case credentials of
                (T.Credentials username password) -> do
                    let pass = mkPassword $ pack password
                    rows <- map (\(Entity _ e) -> e) <$> (runDb $ selectList [Filter UserUserName (FilterValue username) (BackendSpecificFilter "LIKE")] [] :: IO [Entity User])
                    case rows of
                        [user] -> case checkPassword pass (PasswordHash $ pack (userUserPassword user)) of
                            PasswordCheckSuccess -> do
                                rows <- map (\(Entity _ e) -> e) <$> (runDb $ selectList [Filter TokenTokenName (FilterValue username) (BackendSpecificFilter "LIKE")] [] :: IO [Entity Token])
                                response <- if null rows then do
                                    token <- stringRandomIO "[0-9a-zA-Z]{4}-[0-9a-ZA-Z]{10}-[0-9a-zA-Z]{15}"
                                    runDb $ insertEntity $ Token 0 (unpack token) username
                                    return $ unpack token
                                else return $ tokenTokenToken $ head rows
                                return (status200, j2s [aesonQQ|{"token":#{response}}|], jsonHeaders)
                            PasswordCheckFail -> return (status400, messageResponse "Error, Wrong username or password", jsonHeaders)
                        _ -> return (status400, messageResponse "Error, no user exists", jsonHeaders)
                _ -> return (status400, messageResponse "Error, Invalid request", jsonHeaders)
        ),
        ("/brainfuck", \r -> do
            input <- getRequestBodyChunk r
            let result = code $ unpackBS input
            return (status200, result, [("Content-Disposition", "attachment; filename=\"brainfuck.c\"")])
        )
    ]),
    ("GET", [
        ("/visits/get", \_ -> do
            visits <- show . length <$> getVisits
            return (status200, j2s [aesonQQ|{"visits":#{visits}}|], jsonHeaders)
        ),
        ("/guestbook/get", \_ -> do
            entries <- getGuestbook
            return (status200, j2s [aesonQQ|{"entries":#{unpackBS $ toStrict $ encode $ show entries}}|], jsonHeaders)
        )
    ]),
    ("PUT", [
        ("/guestbook/add", \r -> do
            body <- getRequestBodyChunk r
            let entry = getDefault T.EmptyGuestbook (decode (fromStrict body) :: Maybe T.GuestbookEntry)
            case entry of
                (T.GuestbookEntry "" _ _) -> return (status400, messageResponse "Error, name cannot be empty", jsonHeaders)
                (T.GuestbookEntry _ "" _) -> return (status400, messageResponse "Error, content cannot be empty", jsonHeaders)
                (T.GuestbookEntry name content parentId) -> do
                    time <- fmap round getPOSIXTime :: IO Int
                    runDb $ insertEntity $ GuestbookEntry 0 time name content parentId
                    return (status200, messageResponse "Success", jsonHeaders)
        ),
        ("/snake/add", \r -> do
            body <- getRequestBodyChunk r
            let entry = getDefault T.EmptyLeaderboard (decode (fromStrict body) :: Maybe T.LeaderboardEntry)
            case entry of
                T.EmptyLeaderboard -> return (status400, messageResponse "Error, leaderboard empty", jsonHeaders)
                (T.LeaderboardEntry name score speed fruits) -> do
                    time <- fmap round getPOSIXTime :: IO Int
                    runDb $ insertEntity $ Snake 0 time name score speed fruits
                    return (status200, messageResponse "Success", jsonHeaders)
        )
    ]),
    ("DELETE", [

    ])
    ]

api :: Request -> APIResponse
api request = do
    let method = unpackBS $ requestMethod request
    let path = pathInfo request
    case find (\(name, _) -> name == method) apiMap of
        (Just (_, endpoints)) -> case find (\(regex, _) -> (case matchRegex (mkRegex ("api" ++ regex)) $ unpack (intercalate "/" path) of
            Nothing -> False
            _ -> True)) endpoints of
            (Just (_, f)) -> f request
            Nothing -> return (status400, messageResponse "Error, no endpoint found", defaultHeaders)
        Nothing -> return (status400, messageResponse "Error, no endpoint found", defaultHeaders)