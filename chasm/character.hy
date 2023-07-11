"
Functions that deal with characters.
"

(require hyrule.argmove [-> ->>])
(require hyrule.control [unless])

(import chasm [log])

(import chasm.stdlib *)
(import chasm.constants [alphabet
                         appearances
                         default-character])
(import chasm.types [Coords Character Item at?
                     mutable-character-attributes
                     initial-character-attributes])
(import chasm [place])

(import chasm.state [news now world path username
                     characters
                     get-item update-item
                     get-place
                     get-character set-character update-character])
(import chasm.chat [respond yes-no
                    complete-json complete-lines
                    token-length truncate
                    user assistant system
                    msgs->dlg])


(defclass CharacterError [Exception])


(defn spawn [[name None] [coords None]] ; -> Character
  "Spawn a character from card, db, or just generated."
  (try
    (let [card-path (.join "/"[path "characters" f"{name}.json"])
          loaded (or (load card-path)
                     {})
          ; only allow to override some
          sanitised {"name" name
                     "appearance" (:appearance loaded None)
                     "gender" (:gender loaded None)
                     "backstory" (:backstory loaded None)
                     "voice" (:voice loaded None)
                     "traits" (:traits loaded None)
                     "likes" (:likes loaded None)
                     "dislikes" (:dislikes loaded None)
                     "motivation" (:motivation loaded None)}
          coords (or coords (Coords 0 0))]
      (place.extend-map coords)
      (let [char (or (get-character name)
                     (gen-lines coords name)
                     default-character)
            filtered (dfor [k v] (.items sanitised) :if v k v)
            character (Character #** (| (._asdict default-character)
                                        (._asdict char)
                                        filtered))]
        (log.info f"character/spawn {char.name}")
        (when loaded (log.info f"character/spawn loaded: {sanitised}"))
        (when character.name
          (place.extend-map character.coords)
          (set-character character)
          character)))
    (except [e [Exception]]
      (log.error f"character/spawn: failed for {name} at {coords}.")
      (log.error e)
      (when (= username name)
        (raise (ValueError f"Bad spawn for {name}, cannot continue. Check card is valid JSON."))))))

(defn gen-lines [coords [name None]] ; -> Character or None
  "Make up some plausible character based on a name."
  (let [seed (choice alphabet)
        name-str (or name f"the character (whose first name begins with '{seed}')")
        name-dict (if name {"name" name} {})
        place (get-place coords)
        place-name (if place place.name "a typical place in this world")
        card f"name: '{name-str}'
appearance: '{name-str}'s appearance, {(choice appearances)}, {(choice appearances)}, clothes, style etc (unique and memorable)'
gender: 'their gender'
backstory: 'their backstory (10 words, memorable)'
voice: 'their manner of speaking, 2-3 words'
traits: 'shapes behaviour, MBTI, quirks/habits, 4-5 words'
motivation: 'drives their behaviour, 4-5 words'
likes: 'their desires, wants, cravings, guiding philosopher'
dislikes: 'their fears and aversions'
skills: 'what they are particularly good at'
occupation: 'their usual job'
objectives: 'their initial objectives'"
        setting f"Story setting: {world}"
        instruction f"Below is a story setting and a template character card.
Complete the character card for {name-str} whom is found in the story at {place.name}.
Example motivation and objectives might align with typical archetypes like Hero, Mentor, Villain, Informant, Guardian etc.
Make up a brief few words, with comma separated values, for each attribute. Be imaginative and very specific."
        details (complete-lines
                  :context setting
                  :template card
                  :instruction instruction
                  :attributes initial-character-attributes)]
    (log.info f"character/gen '{(:name details None)}'")
    (Character #** (| (._asdict default-character)
                      details
                      name-dict
                      {"coords" coords}))))

(defn gen-json [coords [name None]] ; -> Character or None
  "Make up some plausible character based on a name."
  (let [seed (choice alphabet)
        name-str (or name f"the character (whose first name begins with {seed})")
        name-dict (if name {"name" name} {})
        place (get-place coords)
        place-name (if place place.name "a typical place in this world")
        card f"{{
    \"name\": \"{name-str}\",
    \"appearance\": \"{name-str}'s appearance, {(choice appearances)}, {(choice appearances)}, clothes, style etc (unique and memorable)\",
    \"gender\": \"their gender\",
    \"backstory\": \"their backstory (10 words, memorable)\",
    \"voice\": \"their manner of speaking, 2-3 words\",
    \"traits\": \"shapes their behaviour, 4-5 words\",
    \"motivation\": \"drives their behaviour, 4-5 words\",
    \"likes\": \"their desires, wants and cravings\",
    \"dislikes\": \"their fears and aversions\",
    \"skills\": \"what they are particularly good at\",
    \"occupation\": \"their usual job\",
    \"objectives\": \"their initial objectives\"
}}"
        setting f"Story setting: {world}"
        instruction f"Below is a story setting and a character card.
Complete the character card for {name-str} whom is found in the story at {place.name}.
Example objectives might align with archetypes Hero, Mentor, Villain, Informant, Guardian.
Give one attribute per line, no commentary, examples or other notes, just the card with the details updated.
Make up a brief few words, with comma separated values, for each attribute. Be imaginative and very specific."
        details (complete-json
                  :template card
                  :context setting
                  :instruction instruction)]
    (when details
      (log.info f"character/gen '{(:name details None)}'")
      (Character #** (| (._asdict default-character)
                        details
                        name-dict
                        {"coords" coords})))))

(defn describe [character [long False]]
  "A string that briefly describes the character."
  (if character
      (let [attributes (._asdict character)]
        ; pop off the things we don't want to inject
        (.pop attributes "memories")
        (.pop attributes "coords")
        (.pop attributes "destination")
        (if long
            (json.dumps
              (dfor #(k v) (.items attributes)
                    :if v
                    k v)
              :indent 4)
            f"{character.name} - {character.appearance}"))
      ""))

(defn describe-at [coords [long False]]
  "A string describing any characters at a location."
  (let [all-at (get-at coords)]
    (if all-at
        (.join "\n" ["The following characters (and nobody else) are here with you:"
                     #* (map (fn [c] (describe c :long long)) all-at)])
        "")))
  
(defn list-at-str [coords]
  "Give the names (as prose) of who is here."
  (let [character-names-here (lfor c (get-at coords) c.name)
        n (len character-names-here)]
    (cond (= n 0) ""
          (= n 1) f"{(first character-names-here)} is here."
          :else f"{(.join ", " (butlast character-names-here))} and {(last character-names-here)} are here.")))

(defn get-at [coords]
  "List of characters at a location, excluding player."
  (let [cs (map get-character characters)]
    (if cs
      (lfor character cs
            :if (and (at? coords character.coords)
                     (not (= character.name username)))
            character)
      []))) 

(defn move [character coords]
  "Just set a location."
  (update-character character :coords coords)
  coords)

(defn increment-score? [character messages]
  "Has the character done something worthwhile?"
  (let [setting f"Story setting: {world}"
        objectives f"In the narrative, {character.name} has the following objectives: {character.objectives}"
        query f"Based only on events happening in the last two messages, has {character.name} done anything notable enough to increase their score?"
        msgs (truncate messages :spare-length 200)
        dialogue (msgs->dlg "narrator" character.name msgs)
        verdict (yes-no [(system query)
                         (user setting)]
                        :context (.join "\n\n" [objectives (format-msgs dialogue)])
                        :query query)]
    (log.info f"character/increment-score? {verdict}")
    verdict))

(defn develop-lines [character dialogue]
  "Develop a character's attributes based on the dialogue."
  (let [nearby-places (.replace (place.nearby-str character.coords :name True) "\n" ", ")
        card f"name: {character.name}
appearance: {character.appearance}
health: {character.health}
emotions: {character.emotions}
destination: {nearby-places} or 'stay here'
objectives: {character.objectives}
new_memory: [classification] - any significant or poignant thing worth remembering from the dialogue"
        instruction f"You will be given a template character card for {character.name}, and the transcript of a dialogue involving them, for context.
Update each attribute that has changed in the the character appropriate to the given context.
Destination should be one of those listed or to stay here.
Objectives should align with the plot, the character's role, and evolve slowly.
Classify new memories into [significant], [minor] or [forgettable].
Just omit the original attribute if it is unchanged.
Use a brief few words, comma separated, for each attribute. Be concise and very specific."
        length (+ 200 (token-length [instruction world card card])) ; count card twice to allow the result
        dialogue-str (format-msgs (truncate dialogue :spare-length length))
        context f"Story setting: {world}

The dialogue is as follows:
{dialogue-str}"
        details (complete-lines
                  :context context
                  :template card
                  :instruction instruction
                  :attributes (append "new_memory" mutable-character-attributes))]
    (try
      (let [new-memory (.pop details "new_memory" None)
            new-name (.join  " "
                             (-> details
                                 (.pop "name" character.name)
                                 (.split)
                                 (cut 3)))
            memories (if (and new-memory
                              ; ignore failed memories
                              (not (in "significant or poignant thing worth remembering from this dialogue" new-memory))
                              (not (in "[forgettable]" new-memory))
                              (not (in "[classification]" new-memory)))
                         (append new-memory character.memories)
                         character.memories)
            new-score (if (and character.objectives
                               (similar character.objectives
                                        (:objectives details "")))
                          character.score
                          (inc character.score))]
        (log.info f"character/develop-lines '{character.name}'")
        (update-character character
                          :memories memories
                          :score new-score
                          :name new-name
                          #** details))
      (except [e [Exception]]
        ; generating to template sometimes fails 
        (log.error "Bad character" e)
        (log.error details)))))

(defn develop-json [character dialogue]
  "Develop a character's attributes based on the dialogue."
  (let [nearby-places (.join ", " (place.nearby character.coords :name True))
        card f"{{
    \"name\": \"{character.name}\",
    \"appearance\": \"{character.appearance}\",
    \"health\": \"{character.health}\",
    \"emotions\": \"{character.emotions}\",
    \"destination\": \"{character.destination}\",
    \"objectives\": \"{character.objectives}\",
    \"new_memory\": \"(classification) - any significant or poignant thing worth remembering from the dialogue\"
}}"
        instruction f"You will be given a character card for {character.name}, and the transcript of a dialogue involving them, for context.
Update each attribute that has changed in the the character appropriate to the given context.
Destination should be one of {nearby-places} or \"stay here\".
Objectives (a string) should align with the plot, the character's role, and evolve slowly.
Classify new memories into (significant), (minor) or (forgettable).
Give one attribute per line, no commentary, examples or other notes, just the card with the updated details.
Just omit the original attribute if it is unchanged.
Use a brief few words, comma separated, for each attribute. Be concise and very specific."
        length (+ 200 (token-length [instruction world card card])) ; count card twice to allow the result
        dialogue-str (format-msgs (truncate dialogue :spare-length length))
        setting f"Story setting: {world}
The dialogue is as follows:
{dialogue-str}"
        kvs (complete-json
              :template card
              :instruction instruction
              :context setting)]
    (when kvs
      (let [details (dfor [k v] (.items kvs)
                          :if (in k (append "new_memory" mutable-character-attributes))
                          k v)
            new-memory (.pop details "new_memory" None)
            new-name (.pop details "name" character.name)
            memories (if (and new-memory
                              ; ignore failed memories
                              (not (in "significant or poignant thing worth remembering from this dialogue" new-memory))
                              (not (in "(forgettable)" new-memory))
                              (not (in "(classification)" new-memory)))
                         (append new-memory character.memories)
                         character.memories)
            score (if (and character.objectives
                           (similar character.objectives
                                    (:objectives details "")))
                      character.score
                      (inc character.score))]
        (log.info f"character/develop-json '{character.name}'")
        (update-character character
                          :memories memories
                          :score score
                          :name new-name
                          #** details)))))

(defn recall [character [keywords None]]
  "Recall memories."
  (let [memories (.copy character.memories)
        significant (lfor m memories :if (in "significant" m) m)]
    (shuffle significant)
    ;; ----- ***** -----
    ;; TODO: use vector db to extract most relevant memories rather than random
    ;; ----- ***** -----
    (cut significant 4)))

(defn get-new [messages player]
  "Are any new or existing characters mentioned in the messages?
They will appear at the player's location."
  (let [setting (system f"Story setting: {world}")
        prelude (system f"Give a list of people (if any), one per line, that are obviously referred to in the text as being physically present at the current location ({(place.name player.coords)}) and time. Do not invent new characters. Exclude places and objects, only people's proper names count. Give the names as they appear in the text. Setting and narrative appear below.")
        instruction (user "Now, give the list of characters.")
        char-list (respond (->> (cut messages -6 None)
                                (prepend setting)
                                (prepend prelude)
                                (append instruction)
                                (truncate :spare-length 200)
                                (append (assistant "The list of character names is:")))
                           :max-tokens 50)
        filtered-char-list (->> char-list
                                 (itemize)
                                 (.split :sep "\n")
                                 (map capwords)
                                 (sieve)
                                 (filter (fn [x] (not (fuzzy-in x ["None" "You" "###" "."]))))
                                 (filter (fn [x] (< (len (.split x)) 3))) ; exclude long rambling non-names
                                 (list))]
    (log.info f"character/get-new: {filtered-char-list}")
    (cut filtered-char-list 4)))
