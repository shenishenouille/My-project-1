// Using doit toujours être au début du script. Il sert à ajouter des librairies (fonctionnalités supplémentaires)
using Unity.VisualScripting;
using UnityEngine;
using UnityEngine.InputSystem; // Sert à utiliser le nouveau système d'input (Input System)
// using UnityEngine.UI; // Sert à utiliser les éléments d'interface utilisateur (UI)
// using UnityEngine.AI; // Sert à utiliser le système de navigation (NavMesh)
// using TMPro; // Sert à utiliser le système de texte (TextMeshPro)
// using UnityEngine.SceneManagement; // Sert à gérer les scènes (changer de scène, recharger la scène, etc.)
// using System.Collections; // Sert à utiliser les coroutines (fonctions qui s'exécutent sur plusieurs frames)
// using System.Collections.Generic;// Sert pour utiliser les listes et les dictionnaires


/**
* Script servant à contrôler la lampe de poche du personnage
* @author Maxime Lacasse-Germain
* @date 2026-09-02
* @see mettre le lien ou la référence si le code provient de l'extérieur
*/

// Le nom de la classe commence par une majuscule et dois correspondre au nom du fichier
public class ControleLampePoche : MonoBehaviour
{
    // ==================================================================
    //  SECTIONS DES VARIABLES (AVANT LES FONCTIONS)
    // ==================================================================

    //L'accès public permet de voir dans l'inspecteur ET d'être modifié par un autre script
    public string nom;

    // L'accès privé n'est pas visible dans l'inspecteur MAIS ne peut PAS être modifié par un autre script;
    // Pas très utile si on veut que la variable soit modifiable et modulaire dans l'inspecteur. 
    // Ex: si on a plusieurs lampes de poche dans la scène, on ne pourra pas changer l'intensité de chacune individuellement. Elles auront toutes la même intensité. 
    private float intensite = 1;

    //[SerializeField] est considéré comme privé mais permet de voir dans l'inspecteur. Un bon compris entre modularité et protection des données
    [SerializeField] bool estAllume;

    [SerializeField] InputAction lampePocheAction;

    // Ajouter une variable public ou  [SerializeField] de type GameObject permet de garder une référence à ce dernier pour éviter de le chercher sur la scène
    [SerializeField] GameObject lampePoche;

    // Ajouter une variable un Type particulier (ex: Light, Rigidbody, Animator, etc.) permet de garder une référence à ce dernier pour éviter de le chercher sur la scène.
    // Dans la fonction Start, on peut utiliser GetComponent<Type>() pour récupérer le composant du GameObject auquel le script est attaché et le stocker dans la variable.
    private Light lumiereLampePoche;

    // ==================================================================
    //  SECTIONS DES FONCTIONS
    // ==================================================================

    // Sert à ajouter l'écouteur d'événement lors du chargement du script
    // OnEnable s'exécute avant la fonction Start
    void OnEnable()
    {
        lampePocheAction.Enable();
    }

    // Sert à enlever l'écouteur d'événement et éviter qu'il se déclenche si l'objet n'existe plus
    // OnDisable s'exécute lorsque l'objet est détruit ou lorsque le script/objet est désactivé
    void OnDisable()
    {
        lampePocheAction.Disable();
    }

    // La fonction Start s'exécute une seule fois à l'activation du script
    // Ici on initialise les éléments au lancement du script
    void Start()
    {
        // Récuperer le composant Light sur l'objet lampePoche
        lumiereLampePoche = lampePoche.GetComponent<Light>();
        // Éteindre la lampe de poche par défaut
        // lumiereLampePoche.enabled = false;
        AllumerLampe(false);
    }

    // Update s'exécute une fois par frame (ça dépend de la force de la machine) 
    // C'est ici qu'on met les déplacements, les animations, les changements d'états, qu'on vérifie les événements, etc.
    void Update()
    {
        // Permet d'afficher dans la console des infos de déboggage
        // Debug.Log(lumiereLampePoche.enabled);


        // Si la touche lampePocheAction est enfoncée une seule fois
        if (lampePocheAction.WasPressedThisFrame())
        {
            if (estAllume == true)
            {
                AllumerLampe(false);
            }
            else
            {
                AllumerLampe(true);
            }
        }

        //// Si estAllume est true
        ////// Mettre estAllume à false
        //// Sinon
        ////// Mettre estAllume à true
        //// Fin si

        // Exécuter la fonction AllumerLampe en fonction de estAllume

        // Fin si

    }

    // FixedUpdate s'exécute à un nombre fixe de frame. Sert essentiellement lorsqu'on utilise la physique
    // Pour l'instant on n'en a pas besoin
    // void FixedUpdate()
    // {

    // }


    // Séparer le code en petites fonctions permet de mieux organiser le code et de le rendre plus lisible.
    // Commencer en indiquant la valeur de retour de la fonction (void = rien, int = nombre entier, float = nombre décimal, bool = vrai ou faux, string = texte, etc.)
    // Ensuite le nom de la fonction (toujours en camelCase) et entre parenthèses les paramètres (variables qui sont passées à la fonction)
    // Une fonction peut ne pas avoir de paramètres, mais si elle en a, il faut les indiquer entre parenthèses avec leur type (ex: int, float, bool, string, etc.) et leur nom. 
    // On peut en avoir plusieurs séparés par des virgules.
    void AllumerLampe(bool doitEtreAllume)
    {
        // Activer/Desactiver l'objet lampePoche en fonction de estAllume 
        if (doitEtreAllume)
        {
            estAllume = true;
        }

        else
        {
            estAllume = false;
        }

        lumiereLampePoche.enabled = estAllume;
        // Éteindre la lampe de poche après un nombre aléatoire de secondes entre 3 et 5 secondes si elle est allumée
        // Dans une comparaison, on utilise == pour comparer deux valeurs.
        // Si il y a seulement le nom d'une variable, ça veut dire qu'on vérifie si elle est vraie (true). Si on veut vérifier si elle est fausse (false), on met un ! devant le nom de la variable.
        // if (doitEtreAllume)
        // {
        //     // Générer un nombre aléatoire entre 3 et 5 secondes
        //     float tempsAvantExtinction = Random.Range(3f, 5f);
        //     // Appeler la fonction EteindreLampe après le nombre de secondes généré
        //     Invoke("EteindreLampe", tempsAvantExtinction);
        // }
        if (doitEtreAllume)
        {
            float tempsAvantExtinction = Random.Range(3f, 5f);
            Invoke("EteindreLampe", tempsAvantExtinction);
        }
    }

    void EteindreLampe()
    {
        AllumerLampe(false);
    }
}
