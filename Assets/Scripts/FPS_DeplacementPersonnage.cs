using UnityEngine;
using UnityEngine.InputSystem;

public class FPS_DeplacementPersonnage : MonoBehaviour
{
    [SerializeField] InputAction deplacementInput;
    [SerializeField] InputAction sautInput;
    [SerializeField] InputAction accelerationInput;

    [SerializeField] float vitesseDeplacement = 7.5f;

    [SerializeField] float hauteurSaut = 2f;

    [SerializeField] float gravite = -9.81f;

    float velociteVerticale;

    Vector3 deplacement;
    CharacterController characterController;
    bool estEnCourse = false;

    void OnEnable()
    {
        deplacementInput.Enable();
        sautInput.Enable();
        accelerationInput.Enable();
    }

    void OnDisable()
    {
        deplacementInput.Disable();
        sautInput.Disable();
        accelerationInput.Disable();
    }
    // Start is called once before the first execution of Update after the MonoBehaviour is created
    void Start()
    {
        characterController = GetComponent<CharacterController>();
    }

    // Update is called once per frame
    void Update()
    {
        if (characterController.isGrounded && sautInput.triggered)
        {
            velociteVerticale = Mathf.Sqrt(hauteurSaut * -2f * gravite);
        }

        if (characterController.isGrounded && velociteVerticale < 0)
        {
            velociteVerticale = -2f;
        }
        else
        {
            velociteVerticale += gravite * Time.deltaTime;
        }

        // On récupère les valeurs de déplacement à partir de l'Input System
        deplacement = deplacementInput.ReadValue<Vector2>();//Il s'agit de 4 boutons, donc on peut utiliser ReadValue<Vector2>() pour récupérer les valeurs de déplacement sur les axes x et y.
        estEnCourse = accelerationInput.IsPressed();//Il s'agit d'un seul bouton

        // On calcule le mouvement en fonction de la direction du personnage et de la vitesse de déplacement. Ici x représente les boutons gauche/droite et y les boutons avant/arrière. 
        // On multiplie par la vitesse de déplacement et le temps écoulé depuis la dernière frame pour que le mouvement soit fluide.
        Vector3 mouvement = transform.right * deplacement.x + transform.forward * deplacement.y;
        float vitesseDeplacementActuelle = estEnCourse ? vitesseDeplacement * 2f : vitesseDeplacement;
        characterController.Move(mouvement * vitesseDeplacementActuelle * Time.deltaTime + Vector3.up * velociteVerticale * Time.deltaTime);


    }
}
