{-# LANGUAGE TemplateHaskell   #-}
{-# LANGUAGE TypeFamilies      #-}
{-# LANGUAGE QuasiQuotes       #-}
{-# LANGUAGE OverloadedStrings #-}
-------------------------------------------------------------------------------
-- |
-- Module      :  Renters
-- Copyright   :  (c) Patrick Brisbin 2010 
-- License     :  as-is
--
-- Maintainer  :  pbrisbin@gmail.com
-- Stability   :  unstable
-- Portability :  unportable
--
-------------------------------------------------------------------------------
module Renters where

import Yesod
import Yesod.Comments
import Yesod.Comments.Storage
import Yesod.Form.Core (GFormMonad)
import Yesod.Helpers.Auth
import Yesod.Helpers.Auth.OpenId
import Yesod.Helpers.Auth.Facebook
import Yesod.Helpers.Static

import Data.Time
import System.Locale

import Control.Monad    (unless, forM)
import Data.Char        (isSpace)
import System.Directory (doesFileExist, createDirectoryIfMissing)
import Text.Jasmine     (minifym)

import Database.Persist.GenericSql
import qualified Data.ByteString.Lazy as L
import qualified Data.Map as M
import qualified Data.Text as T

import Model

import qualified Settings

-- | The main site type
data Renters = Renters
    { getStatic :: Static 
    , siteDocs  :: Handler [Document]
    , connPool  :: ConnectionPool 
    }

type Handler     = GHandler   Renters Renters
type Widget      = GWidget    Renters Renters
type FormMonad a = GFormMonad Renters Renters a

-- | Define all of the routes and handlers
mkYesodData "Renters" [parseRoutes|
    /                   RootR    GET

    /search                SearchR        GET
    /search/comp/landlords CompLandlordsR GET
    /search/comp/searches  CompSearchesR  GET

    /new/#ReviewType    NewR     GET POST
    /reviews/#ReviewId  ReviewsR GET POST

    /profile         ProfileR        GET
    /profile/edit    EditProfileR    GET POST
    /profile/delete  DeleteProfileR  GET POST

    /legal              LegalR   GET
    /static             StaticR Static getStatic
    /auth               AuthR   Auth   getAuth

    /favicon.ico FaviconR GET
    /robots.txt  RobotsR  GET
    |]

staticFiles Settings.staticDir

instance Yesod Renters where 
    approot   _ = Settings.approot
    authRoute _ = Just $ AuthR LoginR

    defaultLayout widget = do
        (t,h)   <- breadcrumbs
        mmesg   <- getMessage
        pc      <- widgetToPageContent widget
        mauth   <- maybeAuth
        authNav <- widgetToPageContent (authNavHelper mauth)

        hamletToRepHtml [hamlet|
            \<!DOCTYPE html>
            <html lang="en">
                <head>
                    <meta charset="utf-8">
                    <link href="http://fonts.googleapis.com/css?family=Cardo" rel=stylesheet type=text/css>
                    <title>#{pageTitle pc}
                    <meta name="description" content="Submit and search reviews for landlords in your area.">
                    <meta name="author" content="Patrick Brisbin">
                    <meta name="viewport" content="width=device-width, initial-scale=1.0">
                    <link rel="stylesheet" href="@{StaticR css_style_css}">
                    <script src="//ajax.googleapis.com/ajax/libs/jquery/1.5/jquery.min.js">
                    <script src="//ajax.googleapis.com/ajax/libs/jqueryui/1.8/jquery-ui.min.js">
                    ^{pageHead pc}
                <body>
                    <div #breadcrumbs>
                        <p>
                            $forall node <- h
                                <a href="@{fst node}">#{snd node} 
                                \ > 
                            #{t}

                    <div #right-nav>
                        <p>
                            ^{pageBody authNav}
                            \ | 
                            <a href="@{LegalR}">legal

                    $maybe mesg <- mmesg
                        <div #message>
                            <p>#{mesg}

                    ^{pageBody pc}

                    <footer>
                        <p>
                            <small>copyright patrick brisbin 2011. 
                            <a href="https://github.com/pbrisbin/renters-reality">source code.
            |]

    urlRenderOverride a (StaticR s) = Just $ uncurry (joinPath a (T.pack Settings.staticRoot)) $ renderRoute s
    urlRenderOverride _ _           = Nothing

    addStaticContent ext' _ sContent = do
        let fn = base64md5 sContent ++ '.' : (T.unpack ext')
        let content' =
                if ext' == "js"
                    then case minifym sContent of
                        Left _ -> sContent
                        Right y -> y
                    else sContent
        let statictmp = Settings.staticDir ++ "/tmp/"
        liftIO $ createDirectoryIfMissing True statictmp
        let fn' = statictmp ++ fn
        exists <- liftIO $ doesFileExist fn'
        unless exists $ liftIO $ L.writeFile fn' content'
        return $ Just $ Right (StaticR $ StaticRoute ["tmp", (T.pack fn)] [], [])

instance YesodPersist Renters where
    type YesodDB Renters = SqlPersist
    runDB db = liftIOHandler $ fmap connPool getYesod >>= runSqlPool db

instance YesodBreadcrumbs Renters where
    breadcrumb RootR          = return ("Home"   , Nothing      )
    breadcrumb SearchR        = return ("search" , Just RootR   )
    breadcrumb (ReviewsR _)   = return ("view"   , Just RootR   )
    breadcrumb (NewR _)       = return ("new"    , Just RootR   )
    breadcrumb LegalR         = return ("legal"  , Just RootR   )
    breadcrumb (AuthR _)      = return ("login"  , Just RootR   )
    breadcrumb ProfileR       = return ("profile", Just RootR   )
    breadcrumb EditProfileR   = return ("edit"   , Just ProfileR)
    breadcrumb DeleteProfileR = return ("delete" , Just ProfileR)
    breadcrumb _              = return ("404"    , Just RootR   )

instance YesodComments Renters where
    getComment    = getCommentPersist
    storeComment  = storeCommentPersist
    deleteComment = deleteCommentPersist
    loadComments  = loadCommentsPersist

    displayUser uid = do
        muser <- runDB $ get uid
        case muser of
            Just u  -> return $ T.unpack $ showName u
            Nothing -> return ""

instance YesodAuth Renters where
    type AuthId Renters = UserId

    loginDest _  = ProfileR
    logoutDest _ = RootR

    getAuthId creds = do
        muid <- maybeAuth
        x <- runDB $ getBy $ UniqueIdent $ credsIdent creds
        case (x, muid) of
            (Just (_, i), Nothing) -> return $ Just $ identUser i
            (Nothing, Nothing) -> runDB $ do
                uid <- insert $ User
                    { userFullname      = Nothing
                    , userUsername      = Nothing
                    , userEmail         = Nothing
                    , userVerifiedEmail = False
                    , userVerkey        = Nothing
                    }
                _ <- insert $ Ident (credsIdent creds) uid
                return $ Just uid
            (Nothing, Just (uid, _)) -> do
                setMessage "Identifier added to your account"
                _ <- runDB $ insert $ Ident (credsIdent creds) uid
                return $ Just uid
            (Just _, Just _) -> do
                setMessage "That identifier is already attached to an account. Please detach it from the other account first."
                redirect RedirectTemporary ProfileR

    authPlugins = [ authOpenId 
                  , authFacebook "206687389350404"
                                 "9d30284c6cb99ff2c7cbc4e5f8ae53e0"
                                 []
                  ]

    loginHandler = defaultLayout [hamlet|
        <h1>Log in
        <div .tabdiv>
            <div #login>
                <h3>Please login using one of the following:
                <div .services>
                    <table>
                        <tr>
                            <td>
                                <form method="get" action="@{AuthR forwardUrl}" .button .google>
                                    <input type="hidden" name="openid_identifier" value="https://www.google.com/accounts/o8/id">
                                    <input type="image" src="@{StaticR google_gif}" value="Login via Google">
                            <td>
                                <form method="get" action="@{AuthR forwardUrl}" .button .yahoo>
                                    <input type="hidden" name="openid_identifier" value="http://me.yahoo.com">
                                    <input type="image" src="@{StaticR yahoo_gif}" value="Login via Yahoo!">
                            <td>
                                <a href="@{AuthR facebookUrl}" .button .facebook>
                                    <img src="@{StaticR facebook_gif}" value="Login via Facebook">

                <div .open-id>
                    <h3>&mdash; OR &mdash;
                    <table>
                        <tr>
                            <td>
                                <form method="get" action="@{AuthR forwardUrl}">
                                    <input id="openid_identifier" type="text" name="openid_identifier" value="http://">
                                    <input id="openid_submit" type="submit" value="Login via OpenID">
        |]

authNavHelper :: Maybe (UserId, User) -> GWidget s Renters ()
authNavHelper Nothing         = [hamlet|<a href="@{AuthR LoginR}">login|]
authNavHelper (Just (_, u)) = [hamlet|
    <a href="@{ProfileR}" title="Manage your profile">#{showName u}
    \ | 
    <a href="@{AuthR LogoutR}">logout
    |]

loadDocuments :: Handler [Document]
loadDocuments = do
    users      <- return . M.fromList =<< runDB (selectList [] [UserUsernameAsc] 0 0)
    landlords  <- return . M.fromList =<< runDB (selectList [] [LandlordNameAsc] 0 0)
    properties <- return . M.fromList =<< runDB (selectList [] [PropertyZipAsc ] 0 0)

    reviews <- runDB $ selectList [] [ReviewCreatedDateDesc] 0 0

    docs <- forM reviews $ \(k,v) -> do
        let u = M.lookup (reviewReviewer v) users
        let l = M.lookup (reviewLandlord v) landlords
        let p = M.lookup (reviewProperty v) properties

        case (u, l, p) of
            (Just u' ,Just l', Just p' ) -> return [Document k v l' p' u']
            _                            -> return []

    return $ concat docs

-- | Find or create an entity, returning its key in both cases
findOrCreate :: PersistEntity a => a -> Handler (Key a)
findOrCreate v = return . either fst id =<< runDB (insertBy v)

-- <https://github.com/snoyberg/haskellers/blob/master/Haskellers.hs>
-- <https://github.com/snoyberg/haskellers/blob/master/LICENSE>
humanReadableTimeDiff :: UTCTime -> GHandler s m String
humanReadableTimeDiff t = return . helper . flip diffUTCTime t =<< liftIO getCurrentTime

    where
        minutes :: NominalDiffTime -> Double
        minutes n = realToFrac $ n / 60

        hours :: NominalDiffTime -> Double
        hours   n = minutes n / 60

        days :: NominalDiffTime -> Double
        days    n = hours n / 24

        weeks :: NominalDiffTime -> Double
        weeks   n = days n / 7

        years :: NominalDiffTime -> Double
        years   n = days n / 365

        i2s :: RealFrac a => a -> String
        i2s n = show m where m = truncate n :: Int

        trim = f . f where f = reverse . dropWhile isSpace

        old           = utcToLocalTime utc t
        dow           = trim $! formatTime defaultTimeLocale "%l:%M %p on %A" old
        thisYear      = trim $! formatTime defaultTimeLocale "%b %e" old
        previousYears = trim $! formatTime defaultTimeLocale "%b %e, %Y" old

        helper d 
            | d         < 1  = "just now"
            | d         < 60 = i2s d ++ " seconds ago"
            | minutes d < 2  = "one minute ago"
            | minutes d < 60 =  i2s (minutes d) ++ " minutes ago"
            | hours d   < 2  = "one hour ago"
            | hours d   < 24 = "about " ++ i2s (hours d) ++ " hours ago"
            | days d    < 5  = "at " ++ dow
            | days d    < 10 = i2s (days d)  ++ " days ago"
            | weeks d   < 2  = i2s (weeks d) ++ " week ago"
            | weeks d   < 5  = i2s (weeks d) ++ " weeks ago"
            | years d   < 1  = "on " ++ thisYear
            | otherwise      = "on " ++ previousYears
