using UnityEngine;

public class Transformation : MonoBehaviour
{
    [SerializeField] GameObject personnage;
    [SerializeField] float vitesseDeplacement = 2f;
    [SerializeField] float vitesseRotation = 1f;
    [SerializeField] float distanceMin = 2f;
    [SerializeField] float distanceMax = 5f;


    void Update()
    {
        //Changer le parent dans la hiérarchie
        //transform.parent = personnage.transform;

        //========================================================================
        // Déplacement
        Vector3 deplacement = new Vector3(0, 0, 1);
        //transform.Translate(deplacement * Time.deltaTime, Space.World);
        transform.Translate(deplacement * Time.deltaTime, Space.Self);
        //transform.Translate(Vector3.forward * vitesseDeplacement * Time.deltaTime, Space.Self);

        //========================================================================
        // Rotation sur place
        transform.Rotate(Vector3.up, 1f, Space.World);
        //transform.Rotate(Vector3.up, 1f, Space.Self);

        // Tourner dans un angle précis
        transform.rotation = Quaternion.Euler(0, 45, 0);

        // Tourner autour d'un point précis
        // transform.RotateAround(personnage.transform.position, Vector3.up, vitesseDeplacement * Time.deltaTime);


        //========================================================================
        // Vector3 direction = personnage.transform.position - transform.position;
        // transform.Translate(direction * vitesseDeplacement * Time.deltaTime);
        // transform.LookAt(personnage.transform.position);
        // transform.rotation = Quaternion.LookRotation(direction, Vector3.up); //Fait la même chose que LookAt


        //========================================================================
        Vector3 direction = personnage.transform.position - transform.position;
        float distance = direction.magnitude;
        if (distance > distanceMin && distance < distanceMax)
        {
            Vector3 directionLerp = Vector3.Lerp(transform.position, personnage.transform.position, 0.5f);
            transform.position = directionLerp;

            Quaternion orientation = Quaternion.LookRotation(direction, Vector3.up);
            transform.rotation = Quaternion.Slerp(transform.rotation, orientation, 0.5f);
        }

    }
}
