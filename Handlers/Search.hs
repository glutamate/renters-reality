{-# LANGUAGE QuasiQuotes       #-}
{-# LANGUAGE OverloadedStrings #-}
module Handlers.Search (getSearchR) where

import Yesod
import Yesod.Markdown

import Renters
import Model hiding (shorten)

import qualified Settings

import Control.Applicative ((<$>),(<*>))
import Data.List           (intercalate)
import Data.Time           (getCurrentTime)


data AddrSearch = AddrSearch
    { addrOne   :: Maybe String
    , addrTwo   :: Maybe String
    , addrCity  :: Maybe String
    , addrState :: Maybe String
    , addrZip   :: Maybe String
    }

data SearchResults = ResLandlord [Landlord] 
                   | ResProperty [Property]

data Search = Search
    { searchTerm    :: String
    , searchResults :: SearchResults
    }

getSearchR :: Handler RepHtml
getSearchR = do
    req <- getRequest
    case getParam req "term" of
        Nothing   -> allReviews
        Just ""   -> allReviews
        Just term -> do
            reviews <- undefined
            defaultLayout $ do
                Settings.setTitle "Search results" 
                [hamlet|
                    <h1>Search results
                    <div .tabdiv>
                        $if null reviews
                            ^{noReviews}
                        $else
                            $forall review <- reviews
                                ^{shortReview review}
                    |]

-- | On a property search, the address criteria is POSTed. only zip is 
--   mandatory, specifying any other fields just narrows the search, 
--   resulting in a different db select
--
--   todo: Search on f.e. Steet name only? need the sql /like/ keyword
--
--postSearchR :: Handler RepHtml
--postSearchR = do
--    addr <- addrFromForm
--
--    let criteria = [ PropertyZipEq (addrZip addr) ] -- zip is mandatory
--            ++ maybeCriteria PropertyAddrOneEq (addrOne addr)
--            ++ maybeCriteria PropertyAddrTwoEq (addrTwo addr)
--            ++ maybeCriteria PropertyCityEq    (addrCity addr)
--            ++ maybeCriteria PropertyStateEq   (addrState addr)
--
--    properties <- return . map snd =<< runDB (selectList criteria [] 0 0)
--    reviews    <- reviewsByProperty properties
--
--    defaultLayout [hamlet|
--        <h1>Reviews by area
--        <div .tabdiv>
--            $if null reviews
--                ^{noneFound}
--            $else
--                $forall review <- reviews
--                    ^{shortReview review}
--            |]
--
--    where
--        addrFromForm :: Handler AddrSearch
--        addrFromForm = runFormPost' $ AddrSearch
--            <$> maybeStringInput "addrone"
--            <*> maybeStringInput "addrtwo"
--            <*> maybeStringInput "city"
--            <*> maybeStringInput "state"
--            <*> stringInput "zip"

allReviews :: Handler RepHtml
allReviews = do
    reviews <- runDB $ selectList [] [ReviewCreatedDateDesc] 0 0
    defaultLayout $ do
        Settings.setTitle "All reviews"
        [hamlet|
            <h1>All reviews
            <div .tabdiv>
                $forall review <- reviews
                    ^{shortReview review}
            |]

noReviews :: Widget ()
noReviews = [hamlet|
    <p>
        I'm sorry, there are no reviews that meet your search criteria.

    <p>
        Would you like to 
        <a href="@{NewR Positive}">write 
        <a href="@{NewR Negative}">one
        ?
    |]

shortReview :: (ReviewId, Review) -> Widget ()
shortReview (rid, review) = do
    now       <- lift $ liftIO getCurrentTime
    mreviewer <- lift $ runDB $ get $ reviewReviewer review
    mproperty <- lift $ runDB $ get $ reviewProperty review
    mlandlord <- lift $ runDB $ get $ reviewLandlord review

    let content = markdownToHtml . Markdown . shorten 400 $ reviewContent review
    
    [hamlet|
        <div .review>
            <div .#{show $ reviewType review}>
                <div .property>
                    <p>#{maybe "No landlord info" landlordName mlandlord} - #{maybe "No property info" formatProperty mproperty}
                <div .content>
                    #{content}
                <div .by>
                    <p>
                        Reviewed by #{maybe "anonymous" showName mreviewer} #{humanReadableTimeDiff now $ reviewCreatedDate review}. 
                        <a href="@{ReviewsR $ rid}">View
        |]

formatProperty :: Property -> String
formatProperty p = intercalate ", "
    [ propertyAddrOne p
    , propertyCity    p
    , propertyState   p
    ]

shorten :: Int -> String -> String
shorten n s = if length s > n then take n s ++ "..." else s
